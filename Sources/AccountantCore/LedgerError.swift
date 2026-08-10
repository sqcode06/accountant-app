import Foundation

public enum LedgerError: Error, Equatable {
    case unknownAccount(AccountID)
    case accountNotFound(AccountID)
    case accountArchived(AccountID)
    case accountHasOpenDrafts(AccountID)

    case mixedCurrencies
    case unbalancedTransaction(sum: Decimal)
    case emptyTransaction

    /// A posting's currency disagrees with the currency its account is denominated in.
    ///
    /// Without this check the posting is accepted and then filtered out of every
    /// balance query, so the amount vanishes from the app without an error.
    case accountCurrencyMismatch(AccountID, expected: Currency, actual: Currency)

    case transactionNotFound(TransactionID)
    case transactionFinalized(TransactionID)
    case duplicateTransactionID(TransactionID)
}
