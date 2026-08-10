import Foundation
import AccountantCore

/// Everything the account detail screen needs, computed once.
///
/// Follows the same shape as `DashboardSnapshot` and `ReconciliationSnapshot`:
/// derive a plain value from the ledger, then let the view render it without
/// touching query APIs during `body`.
struct AccountDetailSnapshot: Equatable {

    struct Entry: Identifiable, Equatable {
        let id: TransactionID
        let date: Date
        let memo: String?
        let delta: Money
        let runningBalance: Money

        /// Confirmed against a statement.
        let isCleared: Bool

        /// Still a draft — editable, not yet a trusted fact.
        let isDraft: Bool

        /// The other accounts this transaction touched, for a "→ Groceries" subtitle.
        let counterparties: [String]

        var isInflow: Bool { delta.amount > .zero }

        var title: String {
            let trimmed = memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
            return counterparties.first ?? (isInflow ? "Money in" : "Money out")
        }
    }

    let account: Account
    let currency: Currency

    /// Every posting, cleared or not.
    let balance: Money

    /// Only what the bank has confirmed.
    let clearedBalance: Money

    /// The gap between the two: recorded but not yet seen on a statement.
    let pendingBalance: Money

    /// Newest first, which is how people read an account.
    let entries: [Entry]

    var hasPending: Bool { pendingBalance.amount != .zero }

    var pendingCount: Int { entries.filter { !$0.isCleared }.count }

    static func make(
        from ledger: Ledger,
        account: Account,
        currency: Currency
    ) -> AccountDetailSnapshot {
        let lines = ledger.statement(
            for: account.id,
            currency: currency,
            includeDrafts: true
        )

        let transactionsByID = Dictionary(
            ledger.transactions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var clearedTotal = Decimal.zero
        var entries: [Entry] = []
        entries.reserveCapacity(lines.count)

        for line in lines {
            let transaction = transactionsByID[line.transactionID]

            let ownPostings = transaction?.postings.filter {
                $0.accountID == account.id && $0.money.currency == currency
            } ?? []

            // A line counts as cleared only when every posting behind it is.
            let isCleared = !ownPostings.isEmpty && ownPostings.allSatisfy(\.cleared)
            if isCleared {
                clearedTotal += line.delta.amount
            }

            let counterparties = transaction?.postings
                .filter { $0.accountID != account.id }
                .compactMap { ledger.accounts[$0.accountID]?.name }
                ?? []

            entries.append(
                Entry(
                    id: line.transactionID,
                    date: line.date,
                    memo: line.memo,
                    delta: line.delta,
                    runningBalance: line.balance,
                    isCleared: isCleared,
                    isDraft: transaction?.state == .draft,
                    counterparties: counterparties
                )
            )
        }

        let balanceAmount = lines.last?.balance.amount ?? .zero

        return AccountDetailSnapshot(
            account: account,
            currency: currency,
            balance: Money(balanceAmount, currency: currency),
            clearedBalance: Money(clearedTotal, currency: currency),
            pendingBalance: Money(balanceAmount - clearedTotal, currency: currency),
            entries: Array(entries.reversed())
        )
    }
}
