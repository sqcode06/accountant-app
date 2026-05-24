import Foundation
import AccountantCore

struct ClassificationRuleConfiguration: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var needle: String
    var counterpartyAccountID: AccountID?
    var cleanedMemo: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String? = nil,
        needle: String,
        counterpartyAccountID: AccountID? = nil,
        cleanedMemo: String? = nil,
        isEnabled: Bool = true
    ) {
        let cleanedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMemo = Self.normalizedOptionalText(cleanedMemo)
        let normalizedName = Self.normalizedOptionalText(name)

        self.id = id
        self.name = normalizedName ?? normalizedMemo ?? cleanedNeedle
        self.needle = cleanedNeedle
        self.counterpartyAccountID = counterpartyAccountID
        self.cleanedMemo = normalizedMemo
        self.isEnabled = isEnabled
    }

    var displayName: String {
        name.isEmpty ? needle : name
    }

    func makeRule() -> DescriptionContainsRule? {
        let cleanedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMemo = Self.normalizedOptionalText(cleanedMemo)

        guard isEnabled, !cleanedNeedle.isEmpty else {
            return nil
        }

        guard counterpartyAccountID != nil || normalizedMemo != nil else {
            return nil
        }

        return DescriptionContainsRule(
            cleanedNeedle,
            counterpartyAccountID: counterpartyAccountID,
            cleanedMemo: normalizedMemo
        )
    }

    static func makeClassifier(from configurations: [ClassificationRuleConfiguration]) -> TransactionClassifier {
        let rules: [any ClassificationRule] = configurations.compactMap { configuration in
            guard let rule = configuration.makeRule() else {
                return nil
            }

            return rule as any ClassificationRule
        }

        return TransactionClassifier(rules: rules)
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }
}

extension Array where Element == ClassificationRuleConfiguration {
    var enabledRuleCount: Int {
        filter { $0.makeRule() != nil }.count
    }
}
