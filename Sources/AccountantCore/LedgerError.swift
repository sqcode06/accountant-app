import Foundation

public enum LedgerError: Error, Equatable {
    case unknownAccount(AccountID)
    case accountNotFound(AccountID)
    case accountArchived(AccountID)
    case accountHasOpenDrafts(AccountID)

    case mixedCurrencies
    case unbalancedTransaction(sum: Decimal)
    case emptyTransaction
    case invalidMonetaryAmount
    case invalidCurrencyCode(String)

    /// A posting's currency disagrees with the currency its account is denominated in.
    ///
    /// Without this check the posting is accepted and then filtered out of every
    /// balance query, so the amount vanishes from the app without an error.
    case accountCurrencyMismatch(AccountID, expected: Currency, actual: Currency)

    case transactionNotFound(TransactionID)
    case transactionFinalized(TransactionID)
    case duplicateTransactionID(TransactionID)
}

/// Structural problems that can only arise when rebuilding a ledger from data.
///
/// Normal mutation keeps accounts in a dictionary and checks transaction IDs as
/// they are added. A decoder starts with arrays, though, so it must reject these
/// identities before turning those arrays into live state.
public enum LedgerValidationError: Error, Equatable, Sendable {
    case invalidAccountID(AccountID)
    case duplicateAccountID(AccountID)
    case invalidTransactionID(TransactionID)
}
