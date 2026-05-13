import Foundation

public struct TransactionClassifier: Sendable {
    public var rules: [any ClassificationRule]

    public init(rules: [any ClassificationRule] = []) {
        self.rules = rules
    }

    public mutating func addRule(_ rule: any ClassificationRule) {
        rules.append(rule)
    }

    /// Runs all rules in insertion order and merges their suggestions.
    ///
    /// If several rules suggest the same field, later rules override earlier
    /// ones. If rules suggest different fields, their suggestions are combined.
    public func classify(
        line: BankLine,
        current transaction: Transaction
    ) -> ClassificationSuggestion? {
        var merged = ClassificationSuggestion()

        for rule in rules {
            guard let suggestion = rule.classify(line: line, current: transaction) else {
                continue
            }

            merged.merge(suggestion)
        }

        return merged.isEmpty ? nil : merged
    }

    public func classifiedDraft(
        line: BankLine,
        current transaction: Transaction,
        statementAccountID: AccountID,
        now: Date = Date()
    ) throws -> Transaction {
        let suggestion = classify(line: line, current: transaction)
        return try suggestion.applying(to: transaction, statementAccountID: statementAccountID, now: now)
    }
}
