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
        do {
            return try store.load()
        } catch LedgerStoreError.fileNotFound {
            return Ledger()
        }
    }

    func save(_ ledger: Ledger) async throws {
        try store.save(ledger)
    }
}
