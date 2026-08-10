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

    /// The currency this account is denominated in, if it is denominated at all.
    ///
    /// Balance-bearing accounts (assets, liabilities) normally declare one: a
    /// Swedbank EUR account holds euros and nothing else. When a currency is
    /// declared, the ledger refuses postings in any other currency. That refusal
    /// is the point — without it a foreign-currency posting is accepted and then
    /// silently omitted from every balance query, so the money simply disappears.
    ///
    /// Category-style accounts (income, expense, equity, clearing) normally leave
    /// this `nil`, meaning "accepts any currency". Groceries bought in euros and
    /// groceries bought in dollars both belong in Groceries.
    public var currency: Currency?

    /// User-defined display order. `Ledger.accounts` is an unordered dictionary,
    /// so ordering has to live on the account itself for the app to honour it.
    public var sortOrder: Int

    /// Optional icon name overriding the one derived from `kind`. The core does
    /// not interpret this; the app layer resolves it.
    public var symbolName: String?

    /// Optional semantic colour token. Held as a string so the core stays UI-free.
    public var colorToken: String?

    public init(
        id: AccountID = AccountID(),
        name: String,
        kind: AccountKind = .asset,
        status: AccountStatus = .active,
        currency: Currency? = nil,
        sortOrder: Int = 0,
        symbolName: String? = nil,
        colorToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.currency = currency
        self.sortOrder = sortOrder
        self.symbolName = symbolName
        self.colorToken = colorToken
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, status, currency, sortOrder, symbolName, colorToken
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try c.decode(AccountID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.kind = try c.decodeIfPresent(AccountKind.self, forKey: .kind) ?? .asset
        self.status = try c.decodeIfPresent(AccountStatus.self, forKey: .status) ?? .active
        self.currency = try c.decodeIfPresent(Currency.self, forKey: .currency)
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.symbolName = try c.decodeIfPresent(String.self, forKey: .symbolName)
        self.colorToken = try c.decodeIfPresent(String.self, forKey: .colorToken)
    }
}

public struct Posting: Hashable, Codable, Sendable {
    public let accountID: AccountID
    public let money: Money

    /// Whether the account's external source (usually a bank statement) has
    /// confirmed this posting.
    ///
    /// Deliberately orthogonal to `Transaction.state`. They answer different
    /// questions and both are worth keeping:
    ///
    /// - `state` — *have I confirmed this is correct?* It governs editability.
    /// - `cleared` — *has the bank seen it?* It governs reconciliation.
    ///
    /// A transaction can be finalized but uncleared (you are sure you paid rent;
    /// the bank has not posted it yet), or cleared but still a draft (it shows on
    /// the statement; you have not reviewed the categorisation).
    public var cleared: Bool

    public init(accountID: AccountID, money: Money, cleared: Bool = false) {
        self.accountID = accountID
        self.money = money
        self.cleared = cleared
    }

    private enum CodingKeys: String, CodingKey {
        case accountID, money, cleared
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.accountID = try c.decode(AccountID.self, forKey: .accountID)
        self.money = try c.decode(Money.self, forKey: .money)
        self.cleared = try c.decodeIfPresent(Bool.self, forKey: .cleared) ?? false
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
