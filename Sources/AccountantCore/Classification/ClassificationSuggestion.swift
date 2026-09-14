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
    /// counterparty account is suggested, an explicitly tagged counterparty wins.
    /// Legacy untagged transactions retain the safe fallback of requiring exactly
    /// one non-statement posting; arbitrary splits remain ambiguous.
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

            let index = try counterpartyIndex(
                in: updated,
                statementAccountID: statementAccountID
            )
            let existing = updated.postings[index]
            updated.postings[index] = Posting(
                accountID: accountID,
                money: existing.money,
                cleared: existing.cleared,
                role: existing.role
            )
        }

        updated.touch(now: now)
        try updated.validate()
        return updated
    }

    private func counterpartyIndex(
        in transaction: Transaction,
        statementAccountID: AccountID
    ) throws -> Int {
        let taggedCounterparties = transaction.postings.indices.filter {
            transaction.postings[$0].role == .counterparty
        }

        if taggedCounterparties.count == 1 {
            let index = taggedCounterparties[0]
            guard transaction.postings[index].accountID != statementAccountID else {
                throw ClassificationError.counterpartyPostingNotFound
            }
            return index
        }

        if taggedCounterparties.count > 1 {
            throw ClassificationError.ambiguousCounterpartyPostings
        }

        // A partially tagged transaction is malformed metadata, not a license to
        // guess that its fee (or another special posting) is the counterparty.
        guard transaction.postings.allSatisfy({ $0.role == nil }) else {
            throw ClassificationError.counterpartyPostingNotFound
        }

        // Backward compatibility for old two-posting transactions. Arbitrary
        // legacy splits remain ambiguous rather than choosing the first posting.
        let untaggedCounterparties = transaction.postings.indices.filter {
            transaction.postings[$0].accountID != statementAccountID
        }

        guard !untaggedCounterparties.isEmpty else {
            throw ClassificationError.counterpartyPostingNotFound
        }
        guard untaggedCounterparties.count == 1 else {
            throw ClassificationError.ambiguousCounterpartyPostings
        }
        return untaggedCounterparties[0]
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
