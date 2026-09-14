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

/// One enabled configured rule that matched a sample or imported line.
public struct ClassificationRuleMatch: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let needle: String
    public let counterpartyAccountID: AccountID?
    public let cleanedMemo: String?

    public init(
        id: UUID,
        name: String,
        needle: String,
        counterpartyAccountID: AccountID?,
        cleanedMemo: String?
    ) {
        self.id = id
        self.name = name
        self.needle = needle
        self.counterpartyAccountID = counterpartyAccountID
        self.cleanedMemo = cleanedMemo
    }
}

/// The deterministic result of evaluating stored rules in their saved order.
public struct ClassificationRuleEvaluation: Equatable, Sendable {
    public let suggestion: ClassificationSuggestion?
    public let matches: [ClassificationRuleMatch]
    public let counterpartyWinnerRuleID: UUID?
    public let memoWinnerRuleID: UUID?

    public init(
        suggestion: ClassificationSuggestion?,
        matches: [ClassificationRuleMatch],
        counterpartyWinnerRuleID: UUID?,
        memoWinnerRuleID: UUID?
    ) {
        self.suggestion = suggestion
        self.matches = matches
        self.counterpartyWinnerRuleID = counterpartyWinnerRuleID
        self.memoWinnerRuleID = memoWinnerRuleID
    }
}

public extension Array where Element == ClassificationRuleConfiguration {
    var enabledRuleCount: Int {
        filter { $0.makeRule() != nil }.count
    }

    /// Evaluates configured rules against a real bank line.
    ///
    /// `current` is retained in this API because classifiers may inspect the draft
    /// transaction even though today's description rule does not.
    func evaluate(
        line: BankLine,
        current transaction: Transaction
    ) -> ClassificationRuleEvaluation {
        makeEvaluation { rule in
            rule.classify(line: line, current: transaction)
        }
    }

    /// Evaluates the same description matching and merge behavior for rule trials.
    func evaluate(description: String) -> ClassificationRuleEvaluation {
        makeEvaluation { rule in
            rule.suggestion(matching: description)
        }
    }

    private func makeEvaluation(
        suggestionFor classify: (DescriptionContainsRule) -> ClassificationSuggestion?
    ) -> ClassificationRuleEvaluation {
        var merged = ClassificationSuggestion()
        var matches: [ClassificationRuleMatch] = []
        var counterpartyWinnerRuleID: UUID?
        var memoWinnerRuleID: UUID?

        for configuration in self {
            guard
                let rule = configuration.makeRule(),
                let suggestion = classify(rule)
            else {
                continue
            }

            matches.append(ClassificationRuleMatch(
                id: configuration.id,
                name: configuration.name,
                needle: configuration.needle,
                counterpartyAccountID: suggestion.counterpartyAccountID,
                cleanedMemo: suggestion.cleanedMemo
            ))

            if suggestion.counterpartyAccountID != nil {
                counterpartyWinnerRuleID = configuration.id
            }
            if suggestion.cleanedMemo != nil {
                memoWinnerRuleID = configuration.id
            }
            merged.merge(suggestion)
        }

        return ClassificationRuleEvaluation(
            suggestion: merged.isEmpty ? nil : merged,
            matches: matches,
            counterpartyWinnerRuleID: counterpartyWinnerRuleID,
            memoWinnerRuleID: memoWinnerRuleID
        )
    }
}
