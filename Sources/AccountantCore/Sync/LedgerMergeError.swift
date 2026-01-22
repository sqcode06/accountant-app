import Foundation

public enum LedgerMergeError: Error, Equatable, Sendable {
    case accountNameMismatch(accountID: AccountID, local: String, incoming: String)

    case incomingTransactionNotFinalized(TransactionID)
    case incomingTransactionInvalid(TransactionID)

    case incomingReferencesUnknownAccount(accountID: AccountID, transactionID: TransactionID)

    case transactionIDConflict(id: TransactionID, local: Transaction, incoming: Transaction)
    case transactionOriginConflict(origin: TransactionOrigin, local: Transaction, incoming: Transaction)
}
