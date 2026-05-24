protocol ClassificationRuleRepository: Sendable {
    func loadOrCreate() async throws -> [ClassificationRuleConfiguration]
    func save(_ rules: [ClassificationRuleConfiguration]) async throws
}

struct EmptyClassificationRuleRepository: ClassificationRuleRepository {
    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] { [] }

    func save(_ rules: [ClassificationRuleConfiguration]) async throws {}
}
