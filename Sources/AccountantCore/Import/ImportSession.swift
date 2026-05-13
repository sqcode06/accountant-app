import Foundation

public enum ImportWarning: Equatable, Sendable {
    case missingExternalID
}

public enum ImportError: Error, Equatable, Sendable {
    case unknownAccount(AccountID)
    case accountArchived(AccountID)
    case invalidTransaction
    case duplicateExternalIDInBatch(TransactionOrigin)
}

public enum ImportLineOutcome: Equatable, Sendable {
    case proposed(line: BankLine, draft: Transaction, warnings: [ImportWarning])
    case skippedDuplicate(line: BankLine, origin: TransactionOrigin, existingTransactionID: TransactionID?)
    case failed(line: BankLine, error: ImportError)
}

public struct ImportPreview: Equatable, Sendable {
    public let source: String
    public let outcomes: [ImportLineOutcome]

    public init(source: String, outcomes: [ImportLineOutcome]) {
        self.source = source
        self.outcomes = outcomes
    }
}

public struct ImportApplyReport: Equatable, Sendable {
    public let insertedTransactions: Int
    public let skippedOutcomes: Int

    public init(insertedTransactions: Int, skippedOutcomes: Int) {
        self.insertedTransactions = insertedTransactions
        self.skippedOutcomes = skippedOutcomes
    }
}

public extension ImportPipeline {
    func previewImport(lines: [BankLine], into ledger: Ledger, now: Date = Date()) -> ImportPreview {
        ImportPreview(source: source, outcomes: [])
    }

    func applyImportPreview(_ preview: ImportPreview, to ledger: inout Ledger) throws -> ImportApplyReport {
        ImportApplyReport(insertedTransactions: 0, skippedOutcomes: preview.outcomes.count)
    }
}
