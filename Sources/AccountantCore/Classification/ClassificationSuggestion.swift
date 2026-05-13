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

    /// Merges another suggestion into this one.
    ///
    /// Non-nil fields from `newer` override the current fields. This gives
    /// deterministic "later rule wins" semantics while allowing rules to fill
    /// different fields independently.
    public mutating func merge(_ newer: ClassificationSuggestion) {
        if let accountID = newer.counterpartyAccountID {
            counterpartyAccountID = accountID
        }

        if let memo = newer.cleanedMemo {
            cleanedMemo = memo
        }
    }

    /// Applies a suggestion to a draft transaction and returns a modified copy.
    ///
    /// The method intentionally does not mutate the input transaction. If a
    /// counterparty account is suggested, exactly one non-statement posting must
    /// exist; otherwise, the classification is considered ambiguous and fails.
    public func applying(
        to transaction: Transaction,
        statementAccountID: AccountID,
        now: Date = Date()
    ) throws -> Transaction {
        guard transaction.state == .draft else {
            throw ClassificationError.cannotApplyToFinalized(transaction.id)
        }

        guard !isEmpty else {
            return transaction
        }

        var updated = transaction

        if let memo = cleanedMemo {
            updated.memo = memo
        }

        if let accountID = counterpartyAccountID {
            guard updated.postings.contains(where: { $0.accountID == statementAccountID }) else {
                throw ClassificationError.statementPostingNotFound(statementAccountID)
            }

            let counterpartyIndices = updated.postings.indices.filter {
                updated.postings[$0].accountID != statementAccountID
            }

            guard !counterpartyIndices.isEmpty else {
                throw ClassificationError.counterpartyPostingNotFound
            }

            guard counterpartyIndices.count == 1 else {
                throw ClassificationError.ambiguousCounterpartyPostings
            }

            let index = counterpartyIndices[0]
            let existing = updated.postings[index]
            updated.postings[index] = Posting(
                accountID: accountID,
                money: existing.money
            )
        }

        updated.touch(now: now)
        try updated.validate()
        return updated
    }
}

public extension Optional where Wrapped == ClassificationSuggestion {
    /// Convenience helper for applying optional suggestions in caller code.
    func applying(
        to transaction: Transaction,
        statementAccountID: AccountID,
        now: Date = Date()
    ) throws -> Transaction {
        guard let suggestion = self else { return transaction }
        return try suggestion.applying(to: transaction, statementAccountID: statementAccountID, now: now)
    }
}
