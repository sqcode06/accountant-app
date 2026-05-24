import Foundation

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

    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] {
        let fileURL = fileURL

        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode([ClassificationRuleConfiguration].self, from: data)
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
