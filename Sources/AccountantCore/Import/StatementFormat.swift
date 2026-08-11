import Foundation

/// Where a statement line's direction comes from.
///
/// Not every bank signs its amounts. Swedbank's Estonian export lists every
/// amount as positive and puts the direction in a separate column as `D` or `K`
/// — *deebet* and *kreedit*. Reading that amount at face value turns every
/// expense into income, and the transaction still balances to zero, so nothing
/// downstream notices. It is the quietest way to get a ledger completely wrong.
public enum SignConvention: Hashable, Sendable {
    /// The amount already carries its sign.
    case signedAmount

    /// A separate column says which way the money went.
    ///
    /// Values are matched case-insensitively after trimming.
    case indicatorColumn(name: String, debitValues: Set<String>, creditValues: Set<String>)

    /// Every amount is money leaving, regardless of sign — for card-only exports.
    case alwaysDebit
}

/// Drops rows that are not transactions.
///
/// Statement exports mix real entries with structural ones. Swedbank writes an
/// opening balance row and two turnover rows — one debit, one credit — in the
/// same file. Importing those invents a transaction that never happened and
/// double-counts the month. Revolut marks rows `PENDING` or `REVERTED`, which are
/// not facts yet either.
public struct RowFilter: Hashable, Sendable {
    public let column: String

    /// When set, only rows whose value is in this set are kept.
    public let keep: Set<String>?

    /// When set, rows whose value is in this set are dropped.
    public let drop: Set<String>?

    public init(column: String, keep: Set<String>? = nil, drop: Set<String>? = nil) {
        self.column = column
        self.keep = keep
        self.drop = drop
    }

    public func allows(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let keep, !keep.contains(where: { $0.uppercased() == normalized }) {
            return false
        }

        if let drop, drop.contains(where: { $0.uppercased() == normalized }) {
            return false
        }

        return true
    }
}

/// What to do with a row that has fewer fields than the header.
public enum ShortRowHandling: Hashable, Sendable {
    /// Reject it. Safe default: a genuinely missing field shifts every column
    /// after it, so the values would be read from the wrong places.
    case reject

    /// Pad with empty fields.
    ///
    /// For exports that simply omit trailing empty columns. A row shifted by a
    /// missing *middle* field still tends to fail on its own merits, because the
    /// date will not parse as a date or the currency will not be three letters.
    case padWithEmptyFields
}

/// A complete description of one bank's CSV export.
///
/// Presets rather than a column-mapping screen. Getting a Swedbank file in means
/// knowing that the delimiter is a semicolon, dates are `dd.MM.yyyy`, amounts use
/// a decimal comma, direction lives in a `Debit/Credit` column as `D`/`K`, and
/// row type `82` is a turnover total that must not be imported. That is not
/// knowledge to make somebody reconstruct through a mapping UI on a phone.
public struct StatementFormat: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String

    /// What to expect when picking the file — Swedbank ships a CSV named `.xls`.
    public let note: String?

    public let delimiter: Character
    public let columns: CSVBankLineParser.Columns
    public let dateFormats: [String]
    public let sign: SignConvention
    public let rowFilters: [RowFilter]
    public let shortRows: ShortRowHandling

    public init(
        id: String,
        name: String,
        note: String? = nil,
        delimiter: Character = ",",
        columns: CSVBankLineParser.Columns,
        dateFormats: [String] = ["yyyy-MM-dd"],
        sign: SignConvention = .signedAmount,
        rowFilters: [RowFilter] = [],
        shortRows: ShortRowHandling = .reject
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.delimiter = delimiter
        self.columns = columns
        self.dateFormats = dateFormats
        self.sign = sign
        self.rowFilters = rowFilters
        self.shortRows = shortRows
    }

    public func makeParser(source: String) -> CSVBankLineParser {
        CSVBankLineParser(
            source: source,
            columns: columns,
            delimiter: delimiter,
            dateFormats: dateFormats,
            sign: sign,
            rowFilters: rowFilters,
            shortRows: shortRows
        )
    }
}

public extension StatementFormat {

    static let all: [StatementFormat] = [swedbank, lhv, revolut, generic]

    static func format(id: String) -> StatementFormat {
        all.first { $0.id == id } ?? generic
    }

    /// Swedbank (Estonia). Semicolon-delimited, quoted, decimal comma.
    static let swedbank = StatementFormat(
        id: "swedbank",
        name: "Swedbank",
        note: "Swedbank exports a CSV file named “.csv.xls”. Pick it anyway — it is a CSV.",
        delimiter: ";",
        columns: Columns(
            date: "Date",
            amount: "Amount",
            currency: "Currency",
            description: "Details",
            externalID: "Transfer reference"
        ),
        dateFormats: ["dd.MM.yyyy"],
        sign: .indicatorColumn(
            name: "Debit/Credit",
            debitValues: ["D"],
            creditValues: ["K", "C"]
        ),
        // Row type 20 is a transaction. 10 is the opening balance and 82 is a
        // turnover total written twice, once each way.
        rowFilters: [RowFilter(column: "Row type", keep: ["20"])]
    )

    /// LHV. Comma-delimited, ISO dates, direction in its own column.
    static let lhv = StatementFormat(
        id: "lhv",
        name: "LHV",
        delimiter: ",",
        columns: Columns(
            date: "Date",
            amount: "Amount",
            currency: "Currency",
            description: "Description",
            externalID: "Reference number"
        ),
        dateFormats: ["yyyy-MM-dd"],
        sign: .indicatorColumn(
            name: "Debit/Credit (D/C)",
            debitValues: ["D"],
            creditValues: ["C", "K"]
        ),
        // Observed to omit trailing empty fields.
        shortRows: .padWithEmptyFields
    )

    /// Revolut. Signed amounts, timestamps, a separate fee, and no stable id.
    static let revolut = StatementFormat(
        id: "revolut",
        name: "Revolut",
        note: "Revolut exports carry no unique reference, so duplicate detection falls back to comparing date, amount and description.",
        delimiter: ",",
        columns: Columns(
            date: "Completed Date",
            amount: "Amount",
            currency: "Currency",
            description: "Description",
            externalID: nil,
            fee: "Fee"
        ),
        dateFormats: ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"],
        sign: .signedAmount,
        // Anything not completed is not a fact yet.
        rowFilters: [RowFilter(column: "State", keep: ["COMPLETED"])]
    )

    /// The fallback for banks without a preset.
    static let generic = StatementFormat(
        id: "generic",
        name: "Other bank",
        note: "Expects columns named date, amount, currency, description and external_id.",
        columns: Columns()
    )

    private typealias Columns = CSVBankLineParser.Columns
}
