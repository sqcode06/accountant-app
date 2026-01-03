import Foundation

public struct AccountStatementLine: Hashable, Codable, Sendable {
    public let transactionID: TransactionID
    public let date: Date
    public let memo: String?
    public let delta: Money
    public let balance: Money
}

public extension Ledger {

    /// Returns transactions sorted by (date asc, id asc) for stable output.
    func allTransactionsSorted() -> [Transaction] {
        transactions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    func transactions(in range: ClosedRange<Date>) -> [Transaction] {
        allTransactionsSorted().filter { range.contains($0.date) }
    }

    func transactions(involving accountID: AccountID) -> [Transaction] {
        allTransactionsSorted().filter { tx in
            tx.postings.contains { $0.accountID == accountID }
        }
    }

    func transactions(matching text: String) -> [Transaction] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allTransactionsSorted() }

        return allTransactionsSorted().filter { tx in
            (tx.memo ?? "").lowercased().contains(q)
        }
    }

    /// Balance for a given account, but only including transactions up to (and including) `date`.
    func balance(of accountID: AccountID, currency: Currency, asOf date: Date) -> Money {
        let total = transactions
            .filter { $0.date <= date }
            .flatMap(\.postings)
            .filter { $0.accountID == accountID && $0.money.currency == currency }
            .reduce(Decimal.zero) { $0 + $1.money.amount }

        return Money(total, currency: currency)
    }

    /// Running statement (delta + running balance) for one account & currency.
    func statement(for accountID: AccountID, currency: Currency) -> [AccountStatementLine] {
        var running = Decimal.zero
        var lines: [AccountStatementLine] = []

        for tx in allTransactionsSorted() {
            let deltas = tx.postings
                .filter { $0.accountID == accountID && $0.money.currency == currency }
                .map { $0.money.amount }

            guard !deltas.isEmpty else { continue }

            let deltaSum = deltas.reduce(Decimal.zero, +)
            running += deltaSum

            lines.append(
                AccountStatementLine(
                    transactionID: tx.id,
                    date: tx.date,
                    memo: tx.memo,
                    delta: Money(deltaSum, currency: currency),
                    balance: Money(running, currency: currency)
                )
            )
        }

        return lines
    }
}
