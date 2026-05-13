import Foundation

public struct DescriptionContainsRule: ClassificationRule {
    public let needle: String
    public let counterpartyAccountID: AccountID?
    public let cleanedMemo: String?

    private let normalizedNeedle: String

    public init(
        _ needle: String,
        counterpartyAccountID: AccountID? = nil,
        cleanedMemo: String? = nil
    ) {
        self.needle = needle
        self.counterpartyAccountID = counterpartyAccountID
        self.cleanedMemo = cleanedMemo
        self.normalizedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func classify(
        line: BankLine,
        current transaction: Transaction
    ) -> ClassificationSuggestion? {
        guard !normalizedNeedle.isEmpty else { return nil }

        let haystack = line.description.lowercased()
        guard haystack.contains(normalizedNeedle) else { return nil }

        let suggestion = ClassificationSuggestion(
            counterpartyAccountID: counterpartyAccountID,
            cleanedMemo: cleanedMemo
        )

        return suggestion.isEmpty ? nil : suggestion
    }
}
