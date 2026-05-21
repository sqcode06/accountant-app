import Foundation

public extension ImportPipeline {
    func previewImport(
        lines: [BankLine],
        into ledger: Ledger,
        classifier: TransactionClassifier,
        now: Date = Date()
    ) -> ImportPreview {
        let neutralPreview = previewImport(lines: lines, into: ledger, now: now)

        let classifiedOutcomes = neutralPreview.outcomes.map { outcome in
            switch outcome {
            case .proposed(let line, let draft, let warnings):
                do {
                    let classifiedDraft = try classifier.classifiedDraft(
                        line: line,
                        current: draft,
                        statementAccountID: statementAccountID,
                        now: now
                    )

                    return ImportLineOutcome.proposed(
                        line: line,
                        draft: classifiedDraft,
                        warnings: warnings
                    )
                } catch let error as ClassificationError {
                    return .failed(line: line, error: .classificationFailed(error))
                } catch {
                    return .failed(line: line, error: .invalidTransaction)
                }

            case .skippedDuplicate, .failed:
                return outcome
            }
        }

        return ImportPreview(source: neutralPreview.source, outcomes: classifiedOutcomes)
    }
}