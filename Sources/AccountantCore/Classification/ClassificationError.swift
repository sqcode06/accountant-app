import Foundation

public enum ClassificationError: Error, Equatable, Sendable {
    /// Classification suggestions are only allowed to change drafts.
    case cannotApplyToFinalized(TransactionID)

    /// The transaction does not contain the account the caller says is the
    /// statement/source account.
    case statementPostingNotFound(AccountID)

    /// No non-statement posting exists, so there is no clear counterparty to
    /// reclassify.
    case counterpartyPostingNotFound

    /// More than one non-statement posting exists, so automatic category
    /// replacement would be ambiguous.
    case ambiguousCounterpartyPostings
}
