import Foundation

/// One row that could not be parsed, kept alongside the rows that could.
public struct BankLineRowError: Error, Equatable, Sendable {
    /// 1-based row number in the source text, matching what a spreadsheet shows.
    public let row: Int
    public let error: BankLineParseError

    public init(row: Int, error: BankLineParseError) {
        self.row = row
        self.error = error
    }
}

/// The outcome of parsing a statement: the rows that parsed, and the ones that did not.
///
/// Statements are dirty in practice — one odd date in two hundred rows is normal.
/// Aborting the whole batch for it means the user gets nothing and no way forward,
/// so failures are reported per row and the good rows still come through.
public struct BankLineParseResult: Equatable, Sendable {
    public let lines: [BankLine]
    public let rowErrors: [BankLineRowError]

    public init(lines: [BankLine], rowErrors: [BankLineRowError]) {
        self.lines = lines
        self.rowErrors = rowErrors
    }

    public var hasRowErrors: Bool { !rowErrors.isEmpty }
}

public protocol BankLineParser: Sendable {
    var source: String { get }

    /// Parses every row, collecting per-row failures instead of aborting on the first.
    ///
    /// Still throws for problems that make the whole input unusable — empty text,
    /// a missing header, an absent required column, or CSV that cannot be tokenised.
    /// Those are not recoverable per row.
    func parseLines(_ text: String) throws -> BankLineParseResult
}

public extension BankLineParser {
    /// Strict parse: throws on the first bad row.
    ///
    /// Kept for callers that genuinely want all-or-nothing. Import should prefer
    /// `parseLines` so a single malformed row does not discard the batch.
    func parse(_ text: String) throws -> [BankLine] {
        let result = try parseLines(text)

        if let first = result.rowErrors.first {
            throw first.error
        }

        return result.lines
    }
}

public enum BankLineParseError: Error, Equatable, Sendable {
    case emptyInput
    case missingHeader
    case missingRequiredColumn(String)
    case rowColumnCountMismatch(row: Int, expected: Int, actual: Int)
    case missingRequiredValue(row: Int, column: String)
    case invalidDate(row: Int, column: String, value: String, expectedFormats: [String])
    case invalidAmount(row: Int, column: String, value: String)
    case invalidCurrency(row: Int, column: String, value: String)
    case malformedCSV(row: Int, message: String)
}

public struct CSVBankLineParser: BankLineParser {
    public struct Columns: Hashable, Sendable {
        public var date: String
        public var amount: String
        public var currency: String
        public var description: String
        public var externalID: String?

        /// A separately listed charge, when the bank has one.
        public var fee: String?

        public init(
            date: String = "date",
            amount: String = "amount",
            currency: String = "currency",
            description: String = "description",
            externalID: String? = "external_id",
            fee: String? = nil
        ) {
            self.date = date
            self.amount = amount
            self.currency = currency
            self.description = description
            self.externalID = externalID
            self.fee = fee
        }
    }

    public let source: String
    public var columns: Columns
    public var delimiter: Character
    public var dateFormats: [String]
    public var sign: SignConvention
    public var rowFilters: [RowFilter]
    public var shortRows: ShortRowHandling

    public init(
        source: String,
        columns: Columns = Columns(),
        delimiter: Character = ",",
        dateFormats: [String] = ["yyyy-MM-dd"],
        sign: SignConvention = .signedAmount,
        rowFilters: [RowFilter] = [],
        shortRows: ShortRowHandling = .reject
    ) {
        self.source = source
        self.columns = columns
        self.delimiter = delimiter
        self.dateFormats = dateFormats
        self.sign = sign
        self.rowFilters = rowFilters
        self.shortRows = shortRows
    }

    public func parseLines(_ text: String) throws -> BankLineParseResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BankLineParseError.emptyInput
        }

        let rows = try parseCSVRows(text, delimiter: delimiter)
            .filter { row in
                !row.fields.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard let header = rows.first else {
            throw BankLineParseError.missingHeader
        }

        let headerIndex = makeHeaderIndex(from: header.fields)
        let dateColumn = try requiredColumn(columns.date, in: headerIndex)
        let amountColumn = try requiredColumn(columns.amount, in: headerIndex)
        let currencyColumn = try requiredColumn(columns.currency, in: headerIndex)
        let descriptionColumn = try requiredColumn(columns.description, in: headerIndex)
        let externalIDColumn = columns.externalID.flatMap { headerIndex[normalizedHeader($0)] }
        let feeColumn = columns.fee.flatMap { headerIndex[normalizedHeader($0)] }
        let dateParsers = makeDateParsers()

        // A missing sign column is a whole-file problem, not a per-row one: every
        // row would come out with the wrong direction.
        let signColumn: Int?
        if case let .indicatorColumn(name, _, _) = sign {
            signColumn = try requiredColumn(name, in: headerIndex)
        } else {
            signColumn = nil
        }

        let filters = try rowFilters.map { filter -> (index: Int, filter: RowFilter) in
            (try requiredColumn(filter.column, in: headerIndex), filter)
        }

        var lines: [BankLine] = []
        var rowErrors: [BankLineRowError] = []

        for row in rows.dropFirst() {
            do {
                let padded = try normalizedRow(row, headerFieldCount: header.fields.count)

                // Structural rows — opening balances, turnover totals, pending
                // entries — are skipped silently. They are not failures; they are
                // simply not transactions.
                guard filters.allSatisfy({ $0.filter.allows(value(in: padded, at: $0.index)) }) else {
                    continue
                }

                lines.append(
                    try parseRow(
                        padded,
                        dateColumn: dateColumn,
                        amountColumn: amountColumn,
                        currencyColumn: currencyColumn,
                        descriptionColumn: descriptionColumn,
                        externalIDColumn: externalIDColumn,
                        feeColumn: feeColumn,
                        signColumn: signColumn,
                        dateParsers: dateParsers
                    )
                )
            } catch let error as BankLineParseError {
                rowErrors.append(BankLineRowError(row: row.rowNumber, error: error))
            }
        }

        return BankLineParseResult(lines: lines, rowErrors: rowErrors)
    }

    private func parseRow(
        _ row: ParsedCSVRow,
        dateColumn: Int,
        amountColumn: Int,
        currencyColumn: Int,
        descriptionColumn: Int,
        externalIDColumn: Int?,
        feeColumn: Int?,
        signColumn: Int?,
        dateParsers: [(format: String, formatter: DateFormatter)]
    ) throws -> BankLine {
        let dateText = try requiredValue(in: row, column: dateColumn, name: columns.date)
        let amountText = try requiredValue(in: row, column: amountColumn, name: columns.amount)
        let currencyText = try requiredValue(in: row, column: currencyColumn, name: columns.currency)
        let descriptionText = try requiredValue(in: row, column: descriptionColumn, name: columns.description)
        let externalIDText = externalIDColumn.flatMap { optionalValue(in: row, column: $0) }

        let date = try parseDate(
            dateText,
            row: row.rowNumber,
            column: columns.date,
            parsers: dateParsers
        )
        let rawAmount = try parseAmount(amountText, row: row.rowNumber, column: columns.amount)
        let currency = try parseCurrency(currencyText, row: row.rowNumber, column: columns.currency)

        let amount = try signedAmount(
            rawAmount,
            row: row,
            signColumn: signColumn
        )

        let fee = feeColumn
            .map { value(in: row, at: $0) }
            .flatMap { $0.isEmpty ? nil : DecimalParsing.decimal(from: $0) }
            .map { $0 < .zero ? -$0 : $0 }

        return BankLine(
            date: date,
            amount: amount,
            currency: currency,
            description: descriptionText,
            externalID: externalIDText,
            fee: (fee ?? .zero) == .zero ? nil : fee
        )
    }

    /// Applies the direction the statement declares.
    ///
    /// The magnitude is taken from the amount and the sign from the convention, so
    /// an export that both signs its amounts *and* carries an indicator column
    /// cannot end up double-negated.
    private func signedAmount(
        _ amount: Decimal,
        row: ParsedCSVRow,
        signColumn: Int?
    ) throws -> Decimal {
        let magnitude = amount < .zero ? -amount : amount

        switch sign {
        case .signedAmount:
            return amount

        case .alwaysDebit:
            return -magnitude

        case let .indicatorColumn(name, debitValues, creditValues):
            guard let signColumn else { return amount }

            let raw = value(in: row, at: signColumn)
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            if debitValues.contains(where: { $0.uppercased() == normalized }) {
                return -magnitude
            }

            if creditValues.contains(where: { $0.uppercased() == normalized }) {
                return magnitude
            }

            throw BankLineParseError.missingRequiredValue(row: row.rowNumber, column: name)
        }
    }

    /// Brings a row up to the header's field count, or rejects it.
    ///
    /// Rejecting is the default because a genuinely missing field shifts every
    /// column after it, so values would be read from the wrong places without any
    /// obvious symptom. Padding is opt-in for exports that simply omit trailing
    /// empty columns — and a row shifted by a missing middle field still tends to
    /// fail on its own merits, since the date will not parse as a date.
    private func normalizedRow(_ row: ParsedCSVRow, headerFieldCount: Int) throws -> ParsedCSVRow {
        if row.fields.count == headerFieldCount { return row }

        guard shortRows == .padWithEmptyFields, row.fields.count < headerFieldCount else {
            throw BankLineParseError.rowColumnCountMismatch(
                row: row.rowNumber,
                expected: headerFieldCount,
                actual: row.fields.count
            )
        }

        return ParsedCSVRow(
            rowNumber: row.rowNumber,
            fields: row.fields + Array(
                repeating: "",
                count: headerFieldCount - row.fields.count
            )
        )
    }

    private func value(in row: ParsedCSVRow, at index: Int) -> String {
        guard row.fields.indices.contains(index) else { return "" }
        return row.fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requiredColumn(_ name: String, in headerIndex: [String: Int]) throws -> Int {
        guard let index = headerIndex[normalizedHeader(name)] else {
            throw BankLineParseError.missingRequiredColumn(name)
        }

        return index
    }

    private func requiredValue(in row: ParsedCSVRow, column: Int, name: String) throws -> String {
        let value = row.fields[column].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            throw BankLineParseError.missingRequiredValue(row: row.rowNumber, column: name)
        }

        return value
    }

    private func optionalValue(in row: ParsedCSVRow, column: Int) -> String? {
        let value = row.fields[column].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func parseDate(
        _ value: String,
        row: Int,
        column: String,
        parsers: [(format: String, formatter: DateFormatter)]
    ) throws -> Date {
        for parser in parsers {
            if let date = parser.formatter.date(from: value) {
                return date
            }
        }

        throw BankLineParseError.invalidDate(
            row: row,
            column: column,
            value: value,
            expectedFormats: dateFormats
        )
    }

    private func makeDateParsers() -> [(format: String, formatter: DateFormatter)] {
        dateFormats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            return (format: format, formatter: formatter)
        }
    }

    private func parseAmount(_ value: String, row: Int, column: String) throws -> Decimal {
        // Shared with the rest of the app: statements arrive in whichever
        // convention the bank uses, and this one previously turned "1.234,56"
        // into "1.234.56", which failed outright.
        guard let amount = DecimalParsing.decimal(from: value) else {
            throw BankLineParseError.invalidAmount(row: row, column: column, value: value)
        }

        return amount
    }

    private func parseCurrency(_ value: String, row: Int, column: String) throws -> Currency {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isISOStyleCode = code.count == 3 && code.allSatisfy { $0 >= "A" && $0 <= "Z" }

        guard isISOStyleCode else {
            throw BankLineParseError.invalidCurrency(row: row, column: column, value: value)
        }

        return Currency(code)
    }
}

private struct ParsedCSVRow {
    let rowNumber: Int
    let fields: [String]
}

private func parseCSVRows(_ text: String, delimiter: Character) throws -> [ParsedCSVRow] {
    var rows: [ParsedCSVRow] = []
    var fields: [String] = []
    var field = ""
    var rowNumber = 1
    var isInsideQuotes = false
    var hasPendingRowContent = false
    var didJustCloseQuotedField = false

    var index = text.startIndex

    func finishField() {
        fields.append(field)
        field = ""
    }

    func finishRow() {
        finishField()
        rows.append(ParsedCSVRow(rowNumber: rowNumber, fields: fields))
        fields = []
        hasPendingRowContent = false
        rowNumber += 1
    }

    while index < text.endIndex {
        let character = text[index]

        if character == "\"" {
            hasPendingRowContent = true

            if isInsideQuotes {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes = false
                    didJustCloseQuotedField = true
                }
            } else if field.trimmingCharacters(in: .whitespaces).isEmpty {
                field = ""
                isInsideQuotes = true
                didJustCloseQuotedField = false
            } else {
                throw BankLineParseError.malformedCSV(
                    row: rowNumber,
                    message: "Unexpected quote inside an unquoted field."
                )
            }
        } else if character == delimiter && !isInsideQuotes {
            finishField()
            hasPendingRowContent = true
            didJustCloseQuotedField = false
        } else if (character == "\n" || character == "\r") && !isInsideQuotes {
            finishRow()
            didJustCloseQuotedField = false

            if character == "\r" {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = nextIndex
                }
            }
        } else if didJustCloseQuotedField {
            guard character.isWhitespace else {
                throw BankLineParseError.malformedCSV(
                    row: rowNumber,
                    message: "Unexpected character after closing quote."
                )
            }

            hasPendingRowContent = true
        } else {
            field.append(character)
            hasPendingRowContent = true
        }

        index = text.index(after: index)
    }

    guard !isInsideQuotes else {
        throw BankLineParseError.malformedCSV(row: rowNumber, message: "Unterminated quoted field.")
    }

    if hasPendingRowContent || !field.isEmpty || !fields.isEmpty {
        finishField()
        rows.append(ParsedCSVRow(rowNumber: rowNumber, fields: fields))
    }

    return rows
}

private func makeHeaderIndex(from headers: [String]) -> [String: Int] {
    var index: [String: Int] = [:]

    for (offset, header) in headers.enumerated() {
        let normalized = normalizedHeader(header)
        if index[normalized] == nil {
            index[normalized] = offset
        }
    }

    return index
}

private func normalizedHeader(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if normalized.first == "\u{FEFF}" {
        normalized.removeFirst()
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return normalized.lowercased()
}
