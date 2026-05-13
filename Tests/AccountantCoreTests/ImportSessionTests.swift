import XCTest
@testable import AccountantCore

final class ImportSessionTests: XCTestCase {
    func testPreviewSkipsLineAlreadyImportedByOrigin() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger
        let pipeline = fixture.pipeline
        let existingOrigin = TransactionOrigin(source: "Swedbank", externalID: "X1")

        let existing = Transaction(
            date: Date(timeIntervalSince1970: 100),
            memo: "Already imported",
            postings: [
                Posting(accountID: fixture.bank.id, money: Money(Decimal(-5), currency: fixture.eur)),
                Posting(accountID: fixture.expense.id, money: Money(Decimal(5), currency: fixture.eur))
            ],
            state: .finalized,
            origin: existingOrigin
        )
        try ledger.addTransaction(existing)

        let line = BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-5),
            currency: fixture.eur,
            description: "Same line",
            externalID: "X1"
        )

        let preview = pipeline.previewImport(lines: [line], into: ledger)

        XCTAssertEqual(preview.outcomes.count, 1)
        XCTAssertEqual(
            preview.outcomes.first,
            .skippedDuplicate(line: line, origin: existingOrigin, existingTransactionID: existing.id)
        )
    }

    func testPreviewDetectsDuplicateExternalIDWithinSameBatch() throws {
        let fixture = makeFixture()
        let line1 = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "Coffee", externalID: "X1")
        let line2 = BankLine(date: Date(timeIntervalSince1970: 101), amount: Decimal(-7), currency: fixture.eur, description: "Lunch", externalID: "X1")
        let origin = TransactionOrigin(source: "Swedbank", externalID: "X1")

        let preview = fixture.pipeline.previewImport(lines: [line1, line2], into: fixture.ledger)

        XCTAssertEqual(preview.outcomes.count, 2)

        guard case .proposed(let proposedLine, let draft, let warnings) = preview.outcomes[0] else {
            return XCTFail("First occurrence should be proposed")
        }
        XCTAssertEqual(proposedLine, line1)
        XCTAssertEqual(draft.origin, origin)
        XCTAssertEqual(warnings, [])

        XCTAssertEqual(preview.outcomes[1], .failed(line: line2, error: .duplicateExternalIDInBatch(origin)))
    }

    func testMissingExternalIDProducesWarningButStillProposesDraft() throws {
        let fixture = makeFixture()
        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "No reference", externalID: nil)

        let preview = fixture.pipeline.previewImport(lines: [line], into: fixture.ledger)

        XCTAssertEqual(preview.outcomes.count, 1)
        guard case .proposed(let proposedLine, let draft, let warnings) = preview.outcomes.first else {
            return XCTFail("Line without external ID should still produce a draft")
        }

        XCTAssertEqual(proposedLine, line)
        XCTAssertNil(draft.origin)
        XCTAssertEqual(warnings, [.missingExternalID])
    }

    func testArchivedStatementAccountFailsPreview() throws {
        var fixture = makeFixture()
        try fixture.ledger.archiveAccount(id: fixture.bank.id)
        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "Coffee", externalID: "X1")

        let preview = fixture.pipeline.previewImport(lines: [line], into: fixture.ledger)

        XCTAssertEqual(preview.outcomes, [.failed(line: line, error: .accountArchived(fixture.bank.id))])
    }

    func testArchivedCounterpartyAccountFailsPreview() throws {
        var fixture = makeFixture()
        try fixture.ledger.archiveAccount(id: fixture.expense.id)
        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "Coffee", externalID: "X1")

        let preview = fixture.pipeline.previewImport(lines: [line], into: fixture.ledger)

        XCTAssertEqual(preview.outcomes, [.failed(line: line, error: .accountArchived(fixture.expense.id))])
    }

    func testUnknownCounterpartyAccountFailsPreview() throws {
        let fixture = makeFixture()
        let missingAccountID = AccountID(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        let pipeline = ImportPipeline(source: "Swedbank", statementAccountID: fixture.bank.id, defaultCounterpartyAccountID: missingAccountID)
        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "Coffee", externalID: "X1")

        let preview = pipeline.previewImport(lines: [line], into: fixture.ledger)

        XCTAssertEqual(preview.outcomes, [.failed(line: line, error: .unknownAccount(missingAccountID))])
    }

    func testApplyPreviewIsAtomicWhenAProposedDraftIsInvalid() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger
        let before = ledger

        let validLine = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "Coffee", externalID: "X1")
        let invalidLine = BankLine(date: Date(timeIntervalSince1970: 101), amount: Decimal(-7), currency: fixture.eur, description: "Broken", externalID: "X2")

        let validDraft = try fixture.pipeline.makeDraft(from: validLine)
        let invalidDraft = Transaction.draft(
            date: invalidLine.date,
            memo: invalidLine.description,
            postings: [
                Posting(accountID: fixture.bank.id, money: Money(Decimal(-7), currency: fixture.eur)),
                Posting(accountID: fixture.expense.id, money: Money(Decimal(6), currency: fixture.eur))
            ]
        )

        let preview = ImportPreview(
            source: "Swedbank",
            outcomes: [
                .proposed(line: validLine, draft: validDraft, warnings: []),
                .proposed(line: invalidLine, draft: invalidDraft, warnings: [])
            ]
        )

        XCTAssertThrowsError(try fixture.pipeline.applyImportPreview(preview, to: &ledger))
        XCTAssertEqual(ledger, before)
    }

    func testApplyPreviewInsertsOnlyProposedDrafts() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger
        let validLine = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-5), currency: fixture.eur, description: "Coffee", externalID: "X1")
        let skippedLine = BankLine(date: Date(timeIntervalSince1970: 101), amount: Decimal(-7), currency: fixture.eur, description: "Duplicate", externalID: "X2")
        let failedLine = BankLine(date: Date(timeIntervalSince1970: 102), amount: Decimal(-9), currency: fixture.eur, description: "Failed", externalID: "X3")
        let draft = try fixture.pipeline.makeDraft(from: validLine)
        let skippedOrigin = TransactionOrigin(source: "Swedbank", externalID: "X2")

        let preview = ImportPreview(
            source: "Swedbank",
            outcomes: [
                .proposed(line: validLine, draft: draft, warnings: []),
                .skippedDuplicate(line: skippedLine, origin: skippedOrigin, existingTransactionID: nil),
                .failed(line: failedLine, error: .unknownAccount(AccountID()))
            ]
        )

        let report = try fixture.pipeline.applyImportPreview(preview, to: &ledger)

        XCTAssertEqual(report.insertedTransactions, 1)
        XCTAssertEqual(report.skippedOutcomes, 2)
        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.transactions.first?.state, .draft)
    }

    private func makeFixture() -> (
        eur: Currency,
        ledger: Ledger,
        bank: Account,
        expense: Account,
        pipeline: ImportPipeline
    ) {
        let eur = Currency("EUR")
        let bank = Account(name: "Swedbank", kind: .asset)
        let expense = Account(name: "Uncategorized Expense", kind: .expense)

        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(expense)

        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: expense.id
        )

        return (eur, ledger, bank, expense, pipeline)
    }
}
