import Foundation

public struct AccountID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct TransactionID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum AccountKind: String, Hashable, Codable, Sendable {
    case asset
    case liability
    case income
    case expense
    case equity
    case clearing
}

public enum AccountStatus: String, Hashable, Codable, Sendable {
    case active
    case archived
}

public struct Account: Hashable, Codable, Sendable {
    public let id: AccountID
    public var name: String
    public var kind: AccountKind
    public var status: AccountStatus

    public init(
        id: AccountID = AccountID(),
        name: String,
        kind: AccountKind = .asset,
        status: AccountStatus = .active
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try c.decode(AccountID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)

        // Backward compatibility for ledgers saved before account taxonomy existed.
        self.kind = try c.decodeIfPresent(AccountKind.self, forKey: .kind) ?? .asset
        self.status = try c.decodeIfPresent(AccountStatus.self, forKey: .status) ?? .active
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

public enum TransactionState: String, Codable, Sendable {
    case draft
    case finalized
}

public struct TransactionOrigin: Hashable, Codable, Sendable {
    public var source: String
    public var externalID: String

    public init(source: String, externalID: String) {
        self.source = source
        self.externalID = externalID
    }
}

public struct Transaction: Hashable, Codable, Sendable {
    public let id: TransactionID

    /// “Effective date” (bank date / receipt date / user date).
    public var date: Date

    public var memo: String?
    public var origin: TransactionOrigin?
    public var postings: [Posting]

    public private(set) var state: TransactionState
    public private(set) var createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var finalizedAt: Date?

    public init(
        id: TransactionID = TransactionID(),
        date: Date = Date(),
        memo: String? = nil,
        postings: [Posting],
        state: TransactionState = .draft,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        finalizedAt: Date? = nil,
        origin: TransactionOrigin? = nil
    ) {
        self.id = id
        self.date = date
        self.memo = memo
        self.postings = postings
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.finalizedAt = finalizedAt
        self.origin = origin

        if state == .finalized, self.finalizedAt == nil {
            self.finalizedAt = self.updatedAt
        }
    }

    public static func draft(
        date: Date = Date(),
        memo: String? = nil,
        postings: [Posting]
    ) -> Transaction {
        Transaction(date: date, memo: memo, postings: postings, state: .draft)
    }

    public static func finalized(
        date: Date = Date(),
        memo: String? = nil,
        postings: [Posting]
    ) -> Transaction {
        let now = Date()
        return Transaction(
            date: date,
            memo: memo,
            postings: postings,
            state: .finalized,
            createdAt: now,
            updatedAt: now,
            finalizedAt: now
        )
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

    // MARK: - Lifecycle transitions (internal mutation controlled by Ledger)
    internal mutating func touch(now: Date) {
        updatedAt = now
    }

    internal mutating func finalize(now: Date) {
        state = .finalized
        finalizedAt = now
        updatedAt = now
    }

    // MARK: - Backward compatible decoding (older files won’t have new keys)
    private enum CodingKeys: String, CodingKey {
        case id, date, memo, postings, state, createdAt, updatedAt, finalizedAt, origin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(TransactionID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        memo = try c.decodeIfPresent(String.self, forKey: .memo)
        postings = try c.decode([Posting].self, forKey: .postings)

        state = try c.decodeIfPresent(TransactionState.self, forKey: .state) ?? .draft

        // Sensible defaults for old saves
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        finalizedAt = try c.decodeIfPresent(Date.self, forKey: .finalizedAt)
        origin = try c.decodeIfPresent(TransactionOrigin.self, forKey: .origin)

        if state == .finalized, finalizedAt == nil {
            finalizedAt = updatedAt
        }
    }
}
