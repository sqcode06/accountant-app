import Foundation

public struct TransactionClassifier: Sendable {
    public var rules: [any ClassificationRule]

    public init(rules: [any ClassificationRule] = []) {
        self.rules = rules
    }

    public mutating func addRule(_ rule: any ClassificationRule) {
        rules.append(rule)
    }

    public func classify(
        line: BankLine,
        current transaction: Transaction
    ) -> ClassificationSuggestion? {
        // Stub for contract-test commit. Implementation comes next.
        nil
    }

    public func classifiedDraft(
        line: BankLine,
        current transaction: Transaction,
        statementAccountID: AccountID,
        now: Date = Date()
    ) throws -> Transaction {
        // Stub for contract-test commit. Implementation comes next.
        transaction
    }
}
