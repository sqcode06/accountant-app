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
        try ensureAccountsExist(for: tx)
        transactions.append(tx)
    }

    public mutating func updateDraftTransaction(
        id: TransactionID,
        now: Date = Date(),
        _ edit: (inout Transaction) -> Void
    ) throws {
        let idx = try indexOfTransaction(id)
        var tx = transactions[idx]

        guard tx.state == .draft else { throw LedgerError.transactionFinalized(id) }

        edit(&tx)
        tx.touch(now: now)

        try tx.validate()
        try ensureAccountsExist(for: tx)

        transactions[idx] = tx
    }

    public mutating func finalizeTransaction(id: TransactionID, now: Date = Date()) throws {
        let idx = try indexOfTransaction(id)
        var tx = transactions[idx]

        guard tx.state == .draft else { return } // idempotent

        try tx.validate()
        tx.finalize(now: now)
        transactions[idx] = tx
    }

    public mutating func deleteDraftTransaction(id: TransactionID) throws {
        let idx = try indexOfTransaction(id)
        let tx = transactions[idx]
        guard tx.state == .draft else { throw LedgerError.transactionFinalized(id) }
        transactions.remove(at: idx)
    }

    public func exportFinalizedSnapshot() -> Ledger {
        var out = Ledger()
        out.accounts = self.accounts
        out.transactions = self.transactions.filter { $0.state == .finalized }
        return out
    }

    /// Returns transactions sorted by (date asc, id asc) for stable output.
    public func allTransactionsSorted(includeDrafts: Bool = true) -> [Transaction] {
        let base = includeDrafts ? transactions : transactions.filter { $0.state == .finalized }
        return base.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    public func balance(of accountID: AccountID, currency: Currency) -> Money {
        let total = transactions
            .flatMap(\.postings)
            .filter { $0.accountID == accountID && $0.money.currency == currency }
            .reduce(Decimal.zero) { $0 + $1.money.amount }

        return Money(total, currency: currency)
    }

    // MARK: - Helpers

    private func indexOfTransaction(_ id: TransactionID) throws -> Int {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else {
            throw LedgerError.transactionNotFound(id)
        }
        return idx
    }

    private func ensureAccountsExist(for tx: Transaction) throws {
        for p in tx.postings {
            guard accounts[p.accountID] != nil else {
                throw LedgerError.unknownAccount(p.accountID)
            }
        }
    }

    // MARK: - Internal hooks (module-only)

    internal mutating func _setAccount(_ account: Account) {
        accounts[account.id] = account
    }

    internal mutating func _appendTransaction(_ tx: Transaction) {
        transactions.append(tx)
    }

    internal mutating func _replaceTransaction(id: TransactionID, with tx: Transaction) throws {
        // "replace" must not change identity.
        precondition(tx.id == id, "Attempted to replace transaction \(id) with different id \(tx.id). Use remove+append semantics instead.")
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else {
            throw LedgerError.transactionNotFound(id)
        }
        transactions[idx] = tx
    }

    internal mutating func _removeTransaction(id: TransactionID) throws {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else {
            throw LedgerError.transactionNotFound(id)
        }
        transactions.remove(at: idx)
    }

    internal mutating func _reorderTransactionsCanonically() {
        transactions.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
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
        try c.encode(accounts.values.sorted { 
            $0.id.rawValue.uuidString < $1.id.rawValue.uuidString 
        }, forKey: .accounts)
        try c.encode(transactions, forKey: .transactions)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let accountsArray = try c.decode([Account].self, forKey: .accounts)
        self.accounts = Dictionary(uniqueKeysWithValues: accountsArray.map { ($0.id, $0) })
        self.transactions = try c.decode([Transaction].self, forKey: .transactions)
    }
}
