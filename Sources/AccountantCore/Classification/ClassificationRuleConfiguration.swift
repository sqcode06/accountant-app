import Foundation

/// A classification rule in the form it is stored and edited in.
///
/// Lives in the core rather than the app because it is entirely domain: it holds
/// no view state, depends on nothing above this module, and — the reason it
/// moved — it is a third of what the app's saved state consists of. A backup that
/// could not describe it was not a backup of the app.
public struct ClassificationRuleConfiguration: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var needle: String
    public var counterpartyAccountID: AccountID?
    public var cleanedMemo: String?
    public var isEnabled: Bool

    public init(
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
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case needle
        case counterpartyAccountID
        case cleanedMemo
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let needle = try container.decode(String.self, forKey: .needle)
        let counterpartyAccountID = try container.decodeIfPresent(AccountID.self, forKey: .counterpartyAccountID)
        let cleanedMemo = try container.decodeIfPresent(String.self, forKey: .cleanedMemo)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        self.init(
            id: id,
            name: name,
            needle: needle,
            counterpartyAccountID: counterpartyAccountID,
            cleanedMemo: cleanedMemo,
            isEnabled: isEnabled
        )
    }

    public var displayName: String {
        name.isEmpty ? needle : name
    }

    public func makeRule() -> DescriptionContainsRule? {
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

    public static func makeClassifier(from configurations: [ClassificationRuleConfiguration]) -> TransactionClassifier {
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

public extension Array where Element == ClassificationRuleConfiguration {
    var enabledRuleCount: Int {
        filter { $0.makeRule() != nil }.count
    }
}
