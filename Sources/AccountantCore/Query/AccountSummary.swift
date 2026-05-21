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
    /// Returns account balances for the requested currency.
    ///
    /// Stubbed by the contract-test commit. The implementation commit will
    /// provide deterministic ordering and real balances.
    func accountBalanceSummaries(
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool = false,
        includeArchived: Bool = false
    ) -> [AccountBalanceSummary] {
        []
    }

    /// Returns account balances for accounts of a specific kind.
    func accountBalanceSummaries(
        kind: AccountKind,
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool = false,
        includeArchived: Bool = false
    ) -> [AccountBalanceSummary] {
        []
    }

    /// Returns raw accounting balances grouped by account kind.
    func accountKindBalanceSummaries(
        currency: Currency,
        asOf date: Date,
        includeDrafts: Bool = false,
        includeArchived: Bool = false
    ) -> [AccountKindBalanceSummary] {
        []
    }
}
