import Foundation

public enum ClassificationError: Error, Equatable, Sendable {
    case cannotApplyToFinalized(TransactionID)
    case statementPostingNotFound(AccountID)
    case counterpartyPostingNotFound
    case ambiguousCounterpartyPostings
}
