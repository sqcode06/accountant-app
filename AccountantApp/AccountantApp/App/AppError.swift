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
        case LedgerError.unbalancedTransaction(_):
            self.message = "This transaction is not balanced."

        case TransactionCreationError.nonPositiveAmount(_):
            self.message = "Amount must be greater than zero."

        case ImportError.unknownAccount(_):
            self.message = "An imported transaction references an unknown account."

        case ImportError.accountArchived(_):
            self.message = "An imported transaction references an archived account."

        case ImportError.invalidTransaction:
            self.message = "One of the imported transactions is invalid."

        case ImportError.duplicateExternalIDInBatch(_):
            self.message = "The import contains duplicate external IDs."

        case ImportError.classificationFailed(_):
            self.message = "Import classification failed."
        
        case BankLineParseError.emptyInput:
            self.message = "The CSV input is empty."

        case BankLineParseError.missingHeader:
            self.message = "The CSV file has no header row."

        case BankLineParseError.missingRequiredColumn(_):
            self.message = "The CSV file is missing a required column."

        case BankLineParseError.rowColumnCountMismatch(row: _, expected: _, actual: _):
            self.message = "One CSV row has a different number of columns than the header."

        case BankLineParseError.missingRequiredValue(row: _, column: _):
            self.message = "A required CSV value is missing."

        case BankLineParseError.invalidDate(row: _, column: _, value: _, expectedFormats: _):
            self.message = "A CSV row contains an invalid date."

        case BankLineParseError.invalidAmount(row: _, column: _, value: _):
            self.message = "A CSV row contains an invalid amount."

        case BankLineParseError.invalidCurrency(row: _, column: _, value: _):
            self.message = "A CSV row contains an invalid currency."

        case BankLineParseError.malformedCSV(row: _, message: _):
            self.message = "The CSV file is malformed."
        default:
            self.message = "Something went wrong: \(error.localizedDescription)"
        }
    }
}
