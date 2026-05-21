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
        var grouped: [AccountKind: (amount: Decimal, count: Int)] = [:]

        for summary in accountBalanceSummaries(
            currency: currency,
            asOf: date,
            includeDrafts: includeDrafts,
            includeArchived: includeArchived
        ) {
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
        accounts.values
            .filter { includeArchived || $0.status == .active }
            .filter(predicate)
            .sorted(by: accountBalanceSummarySort)
            .map { account in
                AccountBalanceSummary(
                    account: account,
                    balance: balance(
                        of: account.id,
                        currency: currency,
                        asOf: date,
                        includeDrafts: includeDrafts
                    )
                )
            }
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
