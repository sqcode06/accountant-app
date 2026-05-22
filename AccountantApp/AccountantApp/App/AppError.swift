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
        default:
            self.message = "Something went wrong: \(error.localizedDescription)"
        }
    }
}
