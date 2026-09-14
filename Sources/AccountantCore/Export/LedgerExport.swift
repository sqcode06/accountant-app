import Foundation

/// Gets your data out of the app.
///
/// The ledger file itself is the backup — it is the whole state and it restores
/// exactly. This is the other half of the problem: reading what you have recorded
/// somewhere that is not this app, in a spreadsheet or in whatever your accountant
/// uses.
///
/// One row per **posting**, not per transaction. A transaction here is
/// double-entry — money leaves one account and lands in another, and a bank fee
/// makes a third side — so collapsing it to one row would have to pick a winner
/// and silently drop the rest. Each row repeats its transaction's date, memo and
/// ID, so the file is still readable straight down the page, and rows sharing a
/// transaction ID belong together.
public enum LedgerExport {

    // MARK: - Transactions

    public static func transactionsCSV(
        from ledger: Ledger,
        includeDrafts: Bool = true,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = dateFormatter(for: timeZone)

        var rows: [[String]] = [[
            "Date",
            "Transaction ID",
            "State",
            "Memo",
            "Account",
            "Account kind",
            "Amount",
            "Currency",
            "Cleared",
            "Source",
            "External ID"
        ]]

        for transaction in ledger.allTransactionsSorted(includeDrafts: includeDrafts) {
            for posting in transaction.postings {
                let account = ledger.accounts[posting.accountID]

                rows.append([
                    formatter.string(from: transaction.date),
                    transaction.id.rawValue.uuidString,
                    transaction.state.rawValue,
                    transaction.memo ?? "",
                    // An account that is not in the ledger should be impossible;
                    // naming the orphan beats writing a blank cell if it happens.
                    account?.name ?? "(unknown account \(posting.accountID.rawValue.uuidString))",
                    account?.kind.rawValue ?? "",
                    decimalString(posting.money.amount),
                    posting.money.currency.code,
                    posting.cleared ? "yes" : "no",
                    transaction.origin?.source ?? "",
                    transaction.origin?.externalID ?? ""
                ])
            }
        }

        return csv(from: rows)
    }

    // MARK: - Accounts

    /// The chart of accounts, with each account's balance per currency it holds.
    public static func accountsCSV(
        from ledger: Ledger,
        includeDrafts: Bool = true
    ) -> String {
        var rows: [[String]] = [[
            "Account",
            "Kind",
            "Status",
            "Currency",
            "Balance"
        ]]

        var totals: [AccountID: [Currency: Decimal]] = [:]

        for transaction in ledger.allTransactionsSorted(includeDrafts: includeDrafts) {
            for posting in transaction.postings {
                totals[posting.accountID, default: [:]][posting.money.currency, default: .zero]
                    += posting.money.amount
            }
        }

        for account in ledger.accounts.values.sorted(by: exportOrder) {
            let balances = totals[account.id] ?? [:]

            // An account nothing has touched still belongs in the chart — that is
            // half of what a chart of accounts is for. A balance-bearing account
            // shows a real zero; a category has no currency to be zero *in*, so its
            // balance cell is left blank rather than implying one.
            guard !balances.isEmpty else {
                rows.append([
                    account.name,
                    account.kind.rawValue,
                    account.status.rawValue,
                    account.currency?.code ?? "",
                    account.currency == nil ? "" : decimalString(.zero)
                ])
                continue
            }

            for currency in balances.keys.sorted(by: { $0.code < $1.code }) {
                rows.append([
                    account.name,
                    account.kind.rawValue,
                    account.status.rawValue,
                    currency.code,
                    decimalString(balances[currency] ?? .zero)
                ])
            }
        }

        return csv(from: rows)
    }

    // MARK: - Formatting

    /// Dates as plain `yyyy-MM-dd`.
    ///
    /// No time component: the date on a transaction is the day it happened, not an
    /// instant, and writing 00:00:00 next to it only invites a spreadsheet to
    /// reformat it into something else. Fixed POSIX locale so the output does not
    /// change with the phone's region.
    private static func dateFormatter(for timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Machine-readable amounts: a dot for the decimal point, no grouping, always
    /// two decimal places.
    ///
    /// The point of exporting is that something else reads it, so a locale-formatted
    /// "1 234,56" is out — that is what turns a clean import into an afternoon. The
    /// fixed two places are for the human on the other end: money is written that
    /// way, and a column of 42.50 next to 2400.00 lines up where 42.5 and 2400 do
    /// not. Two places suits every currency this app offers, the same assumption
    /// `AmountEntry` already makes.
    private static func decimalString(_ amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)

        let digits = NSDecimalNumber(decimal: rounded)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: digits) ?? "\(rounded)"
    }

    private static func exportOrder(_ lhs: Account, _ rhs: Account) -> Bool {
        if lhs.kind != rhs.kind {
            return kindOrder(lhs.kind) < kindOrder(rhs.kind)
        }

        let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }

        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    private static func kindOrder(_ kind: AccountKind) -> Int {
        switch kind {
        case .asset: 0
        case .liability: 1
        case .income: 2
        case .expense: 3
        case .equity: 4
        case .clearing: 5
        }
    }

    // MARK: - CSV

    private static func csv(from rows: [[String]]) -> String {
        rows
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n")
            + "\n"
    }

    /// Quotes a field only when it needs it.
    ///
    /// A memo is free text, so it can contain the delimiter, a quote, or a newline
    /// pasted in from a bank statement. Any of those unescaped turns the rest of
    /// the file into garbage from that row onward.
    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")

        guard needsQuoting else { return field }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
