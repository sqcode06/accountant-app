import Foundation
import AccountantCore

/// Sorts an import preview into the four groups the review step shows.
///
/// Lifted out of the old paste-CSV screen, which is the only part of it worth
/// keeping — the grouping is pure logic over `ImportLineOutcome` and has nothing
/// to do with how the statement arrived.
extension ImportPreview {

    var readyOutcomes: [ImportLineOutcome] {
        outcomes.filter {
            if case let .proposed(_, _, warnings) = $0 { return warnings.isEmpty }
            return false
        }
    }

    var warningOutcomes: [ImportLineOutcome] {
        outcomes.filter {
            if case let .proposed(_, _, warnings) = $0 { return !warnings.isEmpty }
            return false
        }
    }

    var duplicateOutcomes: [ImportLineOutcome] {
        outcomes.filter {
            if case .skippedDuplicate = $0 { return true }
            return false
        }
    }

    var failedOutcomes: [ImportLineOutcome] {
        outcomes.filter {
            if case .failed = $0 { return true }
            return false
        }
    }

    /// Everything that would actually be inserted — with and without warnings.
    var importableCount: Int {
        readyOutcomes.count + warningOutcomes.count
    }

    var isEmpty: Bool { outcomes.isEmpty }
}

extension ImportLineOutcome {
    var line: BankLine {
        switch self {
        case let .proposed(line, _, _),
             let .skippedDuplicate(line, _, _),
             let .failed(line, _):
            return line
        }
    }
}

/// Turns import and parse failures into something a person can act on.
///
/// `AppError` already does this for everything that reaches the alert; these are
/// the cases that stay inside the review screen, attached to a specific row.
enum ImportMessages {

    static func rowError(_ error: BankLineRowError, accounts: [AccountID: Account]) -> String {
        "Row \(error.row): \(parseError(error.error))"
    }

    static func parseError(_ error: BankLineParseError) -> String {
        switch error {
        case .emptyInput:
            "The file is empty."
        case .missingHeader:
            "The file has no header row."
        case let .missingRequiredColumn(column):
            "No “\(column)” column. This may be the wrong bank format."
        case let .rowColumnCountMismatch(_, expected, actual):
            "Has \(actual) fields where the header has \(expected)."
        case let .missingRequiredValue(_, column):
            "“\(column)” is empty."
        case let .invalidDate(_, _, value, formats):
            "“\(value)” is not a date in \(formats.joined(separator: " or "))."
        case let .invalidAmount(_, _, value):
            "“\(value)” is not an amount."
        case let .invalidCurrency(_, _, value):
            "“\(value)” is not a currency code. The columns may be misaligned."
        case let .malformedCSV(_, message):
            message
        }
    }

    static func importError(_ error: ImportError, accounts: [AccountID: Account]) -> String {
        switch error {
        case let .unknownAccount(id):
            "References an account that no longer exists (\(name(id, accounts)))."
        case let .accountArchived(id):
            "\(name(id, accounts)) is archived."
        case .invalidTransaction:
            "Could not be turned into a valid transaction."
        case let .duplicateExternalIDInBatch(origin):
            "Appears twice in this file (\(origin.externalID))."
        case .classificationFailed:
            "A rule could not be applied to this line."
        case let .currencyMismatch(id, expected, actual):
            "Is in \(actual.code) but \(name(id, accounts)) holds \(expected.code)."
        case .feeAccountMissing:
            "Has a fee, but no account was chosen to hold fees."
        }
    }

    static func warning(_ warning: ImportWarning) -> String {
        switch warning {
        case .missingExternalID:
            "No reference — duplicates cannot be detected for this line."
        }
    }

    private static func name(_ id: AccountID, _ accounts: [AccountID: Account]) -> String {
        accounts[id]?.name ?? "an unknown account"
    }
}
