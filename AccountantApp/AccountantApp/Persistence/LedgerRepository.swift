import AccountantCore

protocol LedgerRepository: Sendable {
    func loadOrCreate() async throws -> Ledger
    func save(_ ledger: Ledger) async throws
}
