import Foundation

public protocol BankLineParser: Sendable {
    var source: String { get }
    func parse(_ text: String) throws -> [BankLine]
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
    public struct Columns: Equatable, Sendable {
        public var date: String
        public var amount: String
        public var currency: String
        public var description: String
        public var externalID: String?

        public init(
            date: String = "date",
            amount: String = "amount",
            currency: String = "currency",
            description: String = "description",
            externalID: String? = "external_id"
        ) {
            self.date = date
            self.amount = amount
            self.currency = currency
            self.description = description
            self.externalID = externalID
        }
    }

    public let source: String
    public var columns: Columns
    public var delimiter: Character
    public var dateFormats: [String]

    public init(
        source: String,
        columns: Columns = Columns(),
        delimiter: Character = ",",
        dateFormats: [String] = ["yyyy-MM-dd"]
    ) {
        self.source = source
        self.columns = columns
        self.delimiter = delimiter
        self.dateFormats = dateFormats
    }

    public func parse(_ text: String) throws -> [BankLine] {
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

        return try rows.dropFirst().map { row in
            guard row.fields.count == header.fields.count else {
                throw BankLineParseError.rowColumnCountMismatch(
                    row: row.rowNumber,
                    expected: header.fields.count,
                    actual: row.fields.count
                )
            }

            let dateText = try requiredValue(in: row, column: dateColumn, name: columns.date)
            let amountText = try requiredValue(in: row, column: amountColumn, name: columns.amount)
            let currencyText = try requiredValue(in: row, column: currencyColumn, name: columns.currency)
            let descriptionText = try requiredValue(in: row, column: descriptionColumn, name: columns.description)
            let externalIDText = externalIDColumn.flatMap { optionalValue(in: row, column: $0) }

            let date = try parseDate(dateText, row: row.rowNumber, column: columns.date)
            let amount = try parseAmount(amountText, row: row.rowNumber, column: columns.amount)
            let currency = try parseCurrency(currencyText, row: row.rowNumber, column: columns.currency)

            return BankLine(
                date: date,
                amount: amount,
                currency: currency,
                description: descriptionText,
                externalID: externalIDText
            )
        }
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

    private func parseDate(_ value: String, row: Int, column: String) throws -> Date {
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
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

    private func parseAmount(_ value: String, row: Int, column: String) throws -> Decimal {
        let normalized = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
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
                }
            } else if field.isEmpty {
                isInsideQuotes = true
            } else {
                throw BankLineParseError.malformedCSV(
                    row: rowNumber,
                    message: "Unexpected quote inside an unquoted field."
                )
            }
        } else if character == delimiter && !isInsideQuotes {
            finishField()
            hasPendingRowContent = true
        } else if (character == "\n" || character == "\r") && !isInsideQuotes {
            finishRow()

            if character == "\r" {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = nextIndex
                }
            }
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
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
