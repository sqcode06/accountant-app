import Foundation

public struct AccountID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct TransactionID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct Account: Hashable, Codable, Sendable {
    public let id: AccountID
    public var name: String

    public init(id: AccountID = AccountID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct Posting: Hashable, Codable, Sendable {
    public let accountID: AccountID
    public let money: Money

    public init(accountID: AccountID, money: Money) {
        self.accountID = accountID
        self.money = money
    }
}

public struct Transaction: Hashable, Codable, Sendable {
    public let id: TransactionID
    public let date: Date
    public var memo: String?
    public var postings: [Posting]

    public init(
        id: TransactionID = TransactionID(),
        date: Date = Date(),
        memo: String? = nil,
        postings: [Posting]
    ) {
        self.id = id
        self.date = date
        self.memo = memo
        self.postings = postings
    }

    /// Validates classic double-entry invariant:
    /// - at least 2 postings
    /// - single currency per transaction (for now)
    /// - sum(amounts) == 0
    public func validate() throws {
        guard postings.count >= 2 else { throw LedgerError.emptyTransaction }

        let c = postings[0].money.currency
        guard postings.allSatisfy({ $0.money.currency == c }) else {
            throw LedgerError.mixedCurrencies
        }

        let sum = postings.reduce(Decimal.zero) { $0 + $1.money.amount }
        if sum != 0 {
            throw LedgerError.unbalancedTransaction(sum: sum)
        }
    }
}
