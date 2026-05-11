import Foundation

public enum LedgerError: Error, Equatable {
    case unknownAccount(AccountID)
    case accountNotFound(AccountID)
    case accountArchived(AccountID)
    case accountHasOpenDrafts(AccountID)

    case mixedCurrencies
    case unbalancedTransaction(sum: Decimal)
    case emptyTransaction

    case transactionNotFound(TransactionID)
    case transactionFinalized(TransactionID)
    case duplicateTransactionID(TransactionID)
}
