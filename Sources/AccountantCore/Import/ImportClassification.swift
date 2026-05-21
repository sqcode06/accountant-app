import Foundation

public extension ImportPipeline {
    func previewImport(
        lines: [BankLine],
        into ledger: Ledger,
        classifier: TransactionClassifier,
        now: Date = Date()
    ) -> ImportPreview {
        previewImport(lines: lines, into: ledger, now: now)
    }
}