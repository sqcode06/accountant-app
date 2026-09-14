import Foundation
import AccountantCore

protocol AppDataRepository: Sendable {
    func load() async -> AppDataLoadResult
    /// Commits all three components together. A throw before commit leaves the
    /// previous complete snapshot intact; no component is independently saved.
    func save(_ data: LedgerBackup) async throws
    func replaceForRecovery(_ data: LedgerBackup) async throws
    func completeRecovery() async throws
}

extension AppDataRepository {
    func replaceForRecovery(_ data: LedgerBackup) async throws { try await save(data) }
    func completeRecovery() async throws {}
}

struct LocalJSONAppDataRepository: AppDataRepository {
    let store: AppDataStore

    init(directory: URL) { store = AppDataStore(directory: directory) }
    init(store: AppDataStore) { self.store = store }

    static func live() -> Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return Self(directory: base.appendingPathComponent("Accountant", isDirectory: true))
    }

    func load() async -> AppDataLoadResult {
        await Task.detached(priority: .utility) { store.load() }.value
    }

    func save(_ data: LedgerBackup) async throws {
        try await Task.detached(priority: .utility) { try store.save(data) }.value
    }

    func replaceForRecovery(_ data: LedgerBackup) async throws {
        try await Task.detached(priority: .utility) { try store.replaceForRecovery(data) }.value
    }

    func completeRecovery() async throws {
        try await Task.detached(priority: .utility) { try store.completeRecovery() }.value
    }
}
