import Foundation

public struct Ledger: Sendable {
    private(set) public var accounts: [AccountID: Account] = [:]
    private(set) public var transactions: [Transaction] = []

    public init() {}

    public mutating func addAccount(_ account: Account) {
        accounts[account.id] = account
    }

    public mutating func addTransaction(_ tx: Transaction) throws {
        try tx.validate()

        // Ensure all referenced accounts exist
        for p in tx.postings {
            guard accounts[p.accountID] != nil else {
                throw LedgerError.unknownAccount(p.accountID)
            }
        }

        transactions.append(tx)
    }

    public func balance(of accountID: AccountID, currency: Currency) -> Money {
        let total = transactions
            .flatMap(\.postings)
            .filter { $0.accountID == accountID && $0.money.currency == currency }
            .reduce(Decimal.zero) { $0 + $1.money.amount }

        return Money(total, currency: currency)
    }
}

extension Ledger: Equatable {}

extension Ledger: Codable {
    private enum CodingKeys: String, CodingKey {
        case accounts
        case transactions
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Array(accounts.values), forKey: .accounts)
        try c.encode(transactions, forKey: .transactions)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let accountsArray = try c.decode([Account].self, forKey: .accounts)
        self.accounts = Dictionary(uniqueKeysWithValues: accountsArray.map { ($0.id, $0) })
        self.transactions = try c.decode([Transaction].self, forKey: .transactions)
    }
}
