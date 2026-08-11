import Foundation
import AccountantCore

struct LocalJSONLedgerRepository: LedgerRepository {
    let fileURL: URL

    private let store: JSONLedgerStore

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.store = JSONLedgerStore(fileURL: fileURL)
    }

    static func live() -> LocalJSONLedgerRepository {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let appDirectory = baseDirectory.appendingPathComponent(
            "Accountant",
            isDirectory: true
        )

        let fileURL = appDirectory.appendingPathComponent("ledger.json")

        return LocalJSONLedgerRepository(fileURL: fileURL)
    }

    func loadOrCreate() async throws -> Ledger {
        try await Task.detached(priority: .utility) {
            do {
                return try store.load()
            } catch LedgerStoreError.fileNotFound {
                return Ledger()
            }
        }.value
    }

    /// The safe path. Quarantines an unreadable file rather than reporting it as
    /// an error the caller will mistake for emptiness.
    func load() async -> LedgerLoadOutcome {
        await Task.detached(priority: .utility) {
            store.loadOutcome()
        }.value
    }

    func save(_ ledger: Ledger) async throws {
        try await Task.detached(priority: .utility) {
            try store.save(ledger)
        }.value
    }
}
