import Foundation

public enum ImportWarning: Equatable, Sendable {
    case missingExternalID
}

public enum ImportError: Error, Equatable, Sendable {
    case unknownAccount(AccountID)
    case accountArchived(AccountID)
    case invalidTransaction
    case duplicateExternalIDInBatch(TransactionOrigin)
    case classificationFailed(ClassificationError)

    /// A statement line is denominated in a currency the target account does not hold.
    ///
    /// Reported as a per-line failure so the row is visibly rejected in the preview,
    /// rather than being imported and then silently excluded from every balance.
    case currencyMismatch(AccountID, expected: Currency, actual: Currency)

    /// The statement lists a fee but no account was chosen to hold it.
    ///
    /// Reported rather than absorbed: folding the fee into the amount would hide
    /// what charges cost, and dropping it would leave the balance short.
    case feeAccountMissing
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

    func previewImport(
        lines: [BankLine],
        into ledger: Ledger,
        now: Date = Date()
    ) -> ImportPreview {

        var outcomes: [ImportLineOutcome] = []
        var seenOrigins: Set<TransactionOrigin> = []

        for line in lines {

            // Validate statement account first.
            if let error = accountError(for: statementAccountID, in: ledger) {
                outcomes.append(.failed(line: line, error: error))
                continue
            }

            // Validate counterparty account.
            if let error = accountError(for: defaultCounterpartyAccountID, in: ledger) {
                outcomes.append(.failed(line: line, error: error))
                continue
            }

            var warnings: [ImportWarning] = []

            let origin = line.externalID.map {
                TransactionOrigin(source: source, externalID: $0)
            }

            // Missing external IDs are allowed but warned.
            if origin == nil {
                warnings.append(.missingExternalID)
            }

            // Existing duplicate already in ledger.
            if let origin,
               let existingID = existingTransactionID(for: origin, in: ledger) {

                outcomes.append(
                    .skippedDuplicate(
                        line: line,
                        origin: origin,
                        existingTransactionID: existingID
                    )
                )

                continue
            }

            // Duplicate inside current batch.
            if let origin {
                guard !seenOrigins.contains(origin) else {
                    outcomes.append(
                        .failed(
                            line: line,
                            error: .duplicateExternalIDInBatch(origin)
                        )
                    )
                    continue
                }

                seenOrigins.insert(origin)
            }

            let draft: Transaction

            do {
                draft = try makeDraft(from: line, now: now)
            } catch let error as ImportError {
                outcomes.append(.failed(line: line, error: error))
                continue
            } catch {
                outcomes.append(
                    .failed(line: line, error: .invalidTransaction)
                )
                continue
            }

            if let error = firstAccountError(in: draft, ledger: ledger) {
                outcomes.append(.failed(line: line, error: error))
                continue
            }

            outcomes.append(
                .proposed(
                    line: line,
                    draft: draft,
                    warnings: warnings
                )
            )
        }

        return ImportPreview(
            source: source,
            outcomes: outcomes
        )
    }

    func applyImportPreview(
        _ preview: ImportPreview,
        to ledger: inout Ledger
    ) throws -> ImportApplyReport {

        var working = ledger
        var existingOrigins = Set(working.transactions.compactMap(\.origin))

        var insertedTransactions = 0
        var skippedOutcomes = 0

        for outcome in preview.outcomes {
            switch outcome {

            case .proposed(_, let draft, _):
                if let origin = draft.origin, existingOrigins.contains(origin) {
                    skippedOutcomes += 1
                    continue
                }

                try working.addTransaction(draft)

                if let origin = draft.origin {
                    existingOrigins.insert(origin)
                }

                insertedTransactions += 1

            case .skippedDuplicate, .failed:
                skippedOutcomes += 1
            }
        }

        ledger = working

        return ImportApplyReport(
            insertedTransactions: insertedTransactions,
            skippedOutcomes: skippedOutcomes
        )
    }
}

private func existingTransactionID(
    for origin: TransactionOrigin,
    in ledger: Ledger
) -> TransactionID? {

    ledger.transactions.first { $0.origin == origin }?.id
}

private func firstAccountError(
    in transaction: Transaction,
    ledger: Ledger
) -> ImportError? {

    for posting in transaction.postings {
        if let error = accountError(for: posting.accountID, in: ledger) {
            return error
        }

        // An account with no declared currency accepts any currency.
        if let account = ledger.accounts[posting.accountID],
           let declared = account.currency,
           declared != posting.money.currency {

            return .currencyMismatch(
                posting.accountID,
                expected: declared,
                actual: posting.money.currency
            )
        }
    }

    return nil
}

private func accountError(
    for accountID: AccountID,
    in ledger: Ledger
) -> ImportError? {

    guard let account = ledger.accounts[accountID] else {
        return .unknownAccount(accountID)
    }

    guard account.status == .active else {
        return .accountArchived(accountID)
    }

    return nil
}
