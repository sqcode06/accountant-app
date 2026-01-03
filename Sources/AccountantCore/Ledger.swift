import Foundation

public struct Ledger: Codable, Sendable {
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
