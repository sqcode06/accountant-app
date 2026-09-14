import Foundation
import AccountantCore

struct LocalJSONClassificationRuleRepository: ClassificationRuleRepository {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func live() -> LocalJSONClassificationRuleRepository {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let appDirectory = baseDirectory.appendingPathComponent(
            "Accountant",
            isDirectory: true
        )

        let fileURL = appDirectory.appendingPathComponent("classification-rules.json")

        return LocalJSONClassificationRuleRepository(fileURL: fileURL)
    }

    private var store: JSONFileStore<[ClassificationRuleConfiguration]> {
        JSONFileStore(fileURL: fileURL) { [] }
    }

    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] {
        switch await load() {
        case let .loaded(rules): return rules
        case .empty: return []
        case .unreadable: throw StoreRecoveryError.recoveryUnresolved
        }
    }

    /// The safe path — see `LocalJSONBudgetRepository.load()`.
    func load() async -> StoreLoadOutcome<[ClassificationRuleConfiguration]> {
        let store = store

        return await Task.detached(priority: .utility) {
            store.loadOutcome()
        }.value
    }

    func save(_ rules: [ClassificationRuleConfiguration]) async throws {
        let store = store
        try await Task.detached(priority: .utility) {
            try store.save(rules)
        }.value
    }

    func replaceForRecovery(_ rules: [ClassificationRuleConfiguration]) async throws {
        let store = store
        try await Task.detached(priority: .utility) {
            try store.replaceForRecovery(rules)
        }.value
    }

    func completeRecovery() async throws {
        let store = store
        try await Task.detached(priority: .utility) {
            try store.completeRecovery()
        }.value
    }
}
