import AccountantCore

protocol ClassificationRuleRepository: Sendable {
    func loadOrCreate() async throws -> [ClassificationRuleConfiguration]
    func save(_ rules: [ClassificationRuleConfiguration]) async throws

    /// See `LedgerRepository.load()` — same reason, same shape.
    func load() async -> StoreLoadOutcome<[ClassificationRuleConfiguration]>
}

extension ClassificationRuleRepository {
    func load() async -> StoreLoadOutcome<[ClassificationRuleConfiguration]> {
        guard let rules = try? await loadOrCreate() else { return .empty }
        return .loaded(rules)
    }
}

struct EmptyClassificationRuleRepository: ClassificationRuleRepository {
    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] { [] }

    func save(_ rules: [ClassificationRuleConfiguration]) async throws {}
}
