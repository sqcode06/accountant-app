import Foundation

public struct AccountBalanceSummary: Hashable, Codable, Sendable {
    public let account: Account
    public let balance: Money

    public init(account: Account, balance: Money) {
        self.account = account
        self.balance = balance
    }
}

public struct AccountKindBalanceSummary: Hashable, Codable, Sendable {
    public let kind: AccountKind
    public let currency: Currency
    public let balance: Money
    public let accountCount: Int

    public init(kind: AccountKind, currency: Currency, balance: Money, accountCount: Int) {
        self.kind = kind
        self.currency = currency
        self.balance = balance
        self.accountCount = accountCount
    }
}

public extension Ledger {
    /// Returns deterministic account balance summaries for the requested currency.
    ///
    /// Accounts are ordered by account kind, then lowercased name, then stable ID.
    /// Archived accounts are excluded by default, but historical transactions
    /// involving archived accounts still affect balances of active accounts.
    func accountBalanceSummaries(
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool = false,
        includeArchived: Bool = false
    ) -> [AccountBalanceSummary] {
        accountBalanceSummaries(
            matching: { _ in true },
            currency: currency,
            asOf: date,
            includeDrafts: includeDrafts,
            includeArchived: includeArchived
        )
    }

    /// Returns deterministic account balance summaries for accounts of a specific kind.
    func accountBalanceSummaries(
        kind: AccountKind,
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool = false,
        includeArchived: Bool = false
    ) -> [AccountBalanceSummary] {
        accountBalanceSummaries(
            matching: { $0.kind == kind },
            currency: currency,
            asOf: date,
            includeDrafts: includeDrafts,
            includeArchived: includeArchived
        )
    }

    /// Returns raw accounting balances grouped by account kind.
    ///
    /// These are intentionally raw ledger balances. For example, income accounts
    /// usually have negative balances in the current double-entry convention.
    /// Presentation layers may choose to invert signs for user-facing charts.
    func accountKindBalanceSummaries(
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool = false,
        includeArchived: Bool = false
    ) -> [AccountKindBalanceSummary] {
        accountKindBalanceSummaries(
            from: accountBalanceSummaries(
                currency: currency,
                asOf: date,
                includeDrafts: includeDrafts,
                includeArchived: includeArchived
            ),
            currency: currency
        )
    }

    /// Groups already-computed account summaries by kind.
    ///
    /// Callers that need both views — the dashboard does — should compute the
    /// account summaries once and pass them here, rather than calling the
    /// convenience overload above and paying for a second full pass.
    func accountKindBalanceSummaries(
        from summaries: [AccountBalanceSummary],
        currency: Currency
    ) -> [AccountKindBalanceSummary] {
        var grouped: [AccountKind: (amount: Decimal, count: Int)] = [:]

        for summary in summaries {
            let current = grouped[summary.account.kind] ?? (amount: Decimal.zero, count: 0)
            grouped[summary.account.kind] = (
                amount: current.amount + summary.balance.amount,
                count: current.count + 1
            )
        }

        return grouped.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map { kind in
                let value = grouped[kind] ?? (amount: Decimal.zero, count: 0)
                return AccountKindBalanceSummary(
                    kind: kind,
                    currency: currency,
                    balance: Money(value.amount, currency: currency),
                    accountCount: value.count
                )
            }
    }
}

private extension Ledger {
    func accountBalanceSummaries(
        matching predicate: (Account) -> Bool,
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool,
        includeArchived: Bool
    ) -> [AccountBalanceSummary] {
        let totals = accountTotals(
            currency: currency,
            asOf: date,
            includeDrafts: includeDrafts
        )

        return accounts.values
            .filter { includeArchived || $0.status == .active }
            .filter(predicate)
            .sorted(by: accountBalanceSummarySort)
            .map { account in
                AccountBalanceSummary(
                    account: account,
                    balance: Money(totals[account.id] ?? .zero, currency: currency)
                )
            }
    }

    /// Accumulates per-account totals for one currency in a single pass.
    ///
    /// This previously called `balance(of:)` once per account, and each of those
    /// calls walked every transaction in the ledger — O(A·T) work for something
    /// that is naturally O(T+P). With the dashboard recomputing on every render,
    /// that cost was paid continuously.
    ///
    /// The filtering here must stay in step with
    /// `balance(of:currency:asOf:includeDrafts:)` in `LedgerQuery`.
    func accountTotals(
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool
    ) -> [AccountID: Decimal] {
        var totals: [AccountID: Decimal] = [:]

        for tx in transactions {
            guard includeDrafts || tx.state == .finalized else { continue }
            guard tx.date <= date else { continue }

            for posting in tx.postings where posting.money.currency == currency {
                totals[posting.accountID, default: .zero] += posting.money.amount
            }
        }

        return totals
    }
}

private func accountBalanceSummarySort(_ lhs: Account, _ rhs: Account) -> Bool {
    if lhs.kind.rawValue != rhs.kind.rawValue {
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    let leftName = lhs.name.lowercased()
    let rightName = rhs.name.lowercased()
    if leftName != rightName { return leftName < rightName }

    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
}
