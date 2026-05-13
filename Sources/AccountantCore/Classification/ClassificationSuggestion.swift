import Foundation

public struct ClassificationSuggestion: Equatable, Sendable {
    public var counterpartyAccountID: AccountID?
    public var cleanedMemo: String?

    public init(
        counterpartyAccountID: AccountID? = nil,
        cleanedMemo: String? = nil
    ) {
        self.counterpartyAccountID = counterpartyAccountID
        self.cleanedMemo = cleanedMemo
    }

    public var isEmpty: Bool {
        counterpartyAccountID == nil && cleanedMemo == nil
    }

    public mutating func merge(_ newer: ClassificationSuggestion) {
        // Stub for contract-test commit. Implementation comes next.
    }

    public func applying(
        to transaction: Transaction,
        statementAccountID: AccountID,
        now: Date = Date()
    ) throws -> Transaction {
        // Stub for contract-test commit. Implementation comes next.
        transaction
    }
}

public extension Optional where Wrapped == ClassificationSuggestion {
    func applying(
        to transaction: Transaction,
        statementAccountID: AccountID,
        now: Date = Date()
    ) throws -> Transaction {
        guard let suggestion = self else { return transaction }
        return try suggestion.applying(to: transaction, statementAccountID: statementAccountID, now: now)
    }
}
