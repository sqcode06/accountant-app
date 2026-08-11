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
        case .empty, .unreadable: return []
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
        let fileURL = fileURL

        try await Task.detached(priority: .utility) {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let data = try Self.encoder.encode(rules)
            try data.write(to: fileURL, options: [.atomic])
        }.value
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
