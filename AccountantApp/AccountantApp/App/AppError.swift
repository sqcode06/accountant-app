import Foundation
import AccountantCore

struct AppError: Identifiable {
    let id = UUID()
    let message: String

    init(message: String) {
        self.message = message
    }

    init(_ error: Error) {
        switch error {
        case LedgerStoreError.fileNotFound:
            self.message = "No ledger file was found."
        case let LedgerStoreError.unsupportedSchemaVersion(version):
            self.message = "This ledger file uses unsupported schema version \(version)."
        case LedgerError.accountNotFound, LedgerError.unknownAccount:
            self.message = "This account could not be found."
        case LedgerError.accountArchived:
            self.message = "This account is archived. Restore it before using it for new changes."
        case LedgerError.accountHasOpenDrafts:
            self.message = "This account has open draft transactions. Finalize or remove them before archiving it."
        case LedgerError.transactionNotFound:
            self.message = "This transaction could not be found."
        case LedgerError.transactionFinalized:
            self.message = "This transaction is finalized and cannot be edited."
        case LedgerError.mixedCurrencies:
            self.message = "This transaction mixes currencies. Use an explicit conversion transaction instead."
        case LedgerError.unbalancedTransaction:
            self.message = "This transaction is not balanced."
        case LedgerError.emptyTransaction:
            self.message = "This transaction has no postings."
        case LedgerError.duplicateTransactionID:
            self.message = "A transaction with this ID already exists."
        default:
            self.message = "Something went wrong: \(error.localizedDescription)"
        }
    }
}
