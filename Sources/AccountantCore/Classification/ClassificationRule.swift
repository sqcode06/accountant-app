import Foundation

public protocol ClassificationRule: Sendable {
    /// Returns a suggestion for a bank line and its current draft transaction.
    ///
    /// Rules must be pure: they should inspect inputs and return a suggestion,
    /// not mutate ledger or transaction state.
    func classify(line: BankLine, current transaction: Transaction) -> ClassificationSuggestion?
}
