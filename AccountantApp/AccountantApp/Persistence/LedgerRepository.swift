import AccountantCore

protocol LedgerRepository: Sendable {
    func loadOrCreate() async throws -> Ledger
    func save(_ ledger: Ledger) async throws

    /// Reads the store, distinguishing "nothing yet" from "damaged".
    ///
    /// `loadOrCreate` cannot express that difference — it either returns a ledger
    /// or throws, and every caller read a throw as "start empty", which is what
    /// let an unreadable file get overwritten.
    func load() async -> LedgerLoadOutcome
}

extension LedgerRepository {
    /// Default for in-memory and preview repositories, which have no file to
    /// damage. File-backed repositories override this.
    func load() async -> LedgerLoadOutcome {
        guard let ledger = try? await loadOrCreate() else { return .empty }
        return .loaded(ledger)
    }
}
