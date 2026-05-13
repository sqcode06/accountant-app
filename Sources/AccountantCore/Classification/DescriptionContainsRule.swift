import Foundation

public struct DescriptionContainsRule: ClassificationRule {
    public let needle: String
    public let counterpartyAccountID: AccountID?
    public let cleanedMemo: String?

    public init(
        _ needle: String,
        counterpartyAccountID: AccountID? = nil,
        cleanedMemo: String? = nil
    ) {
        self.needle = needle
        self.counterpartyAccountID = counterpartyAccountID
        self.cleanedMemo = cleanedMemo
    }

    public func classify(
        line: BankLine,
        current transaction: Transaction
    ) -> ClassificationSuggestion? {
        // Stub for contract-test commit. Implementation comes next.
        nil
    }
}
