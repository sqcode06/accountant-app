import XCTest
@testable import AccountantCore

final class ImportClassificationTests: XCTestCase {
    func testClassifiedPreviewUpdatesProposedDraftCounterpartyAccount() throws {
        let fixture = makeFixture()
        let line = fixture.line(description: "RIMI EESTI")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("rimi", counterpartyAccountID: fixture.groceries.id)
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        XCTAssertEqual(preview.source, "Swedbank")
        XCTAssertEqual(preview.outcomes.count, 1)

        guard case .proposed(let proposedLine, let draft, let warnings) = preview.outcomes.first else {
            return XCTFail("Expected classified import to keep the line proposed")
        }

        XCTAssertEqual(proposedLine, line)
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(draft.state, .draft)
        XCTAssertEqual(draft.origin, TransactionOrigin(source: "Swedbank", externalID: "X1"))
        XCTAssertEqual(draft.updatedAt, fixture.now)

        XCTAssertEqual(draft.postings.count, 2)
        XCTAssertEqual(
            draft.postings[0],
            Posting(
                accountID: fixture.bank.id,
                money: Money(Decimal(-12), currency: fixture.eur),
                role: .statement
            )
        )
        XCTAssertEqual(
            draft.postings[1],
            Posting(
                accountID: fixture.groceries.id,
                money: Money(Decimal(12), currency: fixture.eur),
                role: .counterparty
            )
        )
    }

    func testClassifiedPreviewUpdatesProposedDraftMemo() throws {
        let fixture = makeFixture()
        let line = fixture.line(description: "RIMI EESTI 1234")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("rimi", cleanedMemo: "Rimi")
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, let warnings) = preview.outcomes.first else {
            return XCTFail("Expected classified import to keep the line proposed")
        }

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(draft.memo, "Rimi")
        XCTAssertEqual(draft.postings[1].accountID, fixture.uncategorized.id)
        XCTAssertEqual(draft.updatedAt, fixture.now)
    }

    func testClassifiedPreviewCanUpdateMemoAndCounterpartyTogether() throws {
        let fixture = makeFixture()
        let line = fixture.line(description: "BOLT FOOD TALLINN")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "bolt food",
                counterpartyAccountID: fixture.food.id,
                cleanedMemo: "Bolt Food"
            )
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, let warnings) = preview.outcomes.first else {
            return XCTFail("Expected classified import to keep the line proposed")
        }

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(draft.memo, "Bolt Food")
        XCTAssertEqual(draft.postings[1].accountID, fixture.food.id)
        XCTAssertEqual(draft.updatedAt, fixture.now)
    }

    func testNonMatchingClassifierLeavesProposedDraftUnchanged() throws {
        let fixture = makeFixture()
        let line = fixture.line(description: "SELVER")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, let warnings) = preview.outcomes.first else {
            return XCTFail("Expected non-matching classifier to keep neutral draft proposed")
        }

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(draft.memo, line.description)
        XCTAssertEqual(draft.postings[0].accountID, fixture.bank.id)
        XCTAssertEqual(draft.postings[1].accountID, fixture.uncategorized.id)
        XCTAssertEqual(draft.updatedAt, fixture.now)
    }

    func testExistingImportWarningsArePreservedWhenClassificationApplies() throws {
        let fixture = makeFixture()
        let line = fixture.line(description: "RIMI EESTI", externalID: nil)
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(let proposedLine, let draft, let warnings) = preview.outcomes.first else {
            return XCTFail("Expected missing-origin line to remain proposed with a warning")
        }

        XCTAssertEqual(proposedLine, line)
        XCTAssertEqual(warnings, [.missingExternalID])
        XCTAssertNil(draft.origin)
        XCTAssertEqual(draft.memo, "Rimi")
        XCTAssertEqual(draft.postings[1].accountID, fixture.groceries.id)
    }

    func testSkippedDuplicateOutcomesAreNotClassified() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger
        let origin = TransactionOrigin(source: "Swedbank", externalID: "X1")
        let existing = Transaction(
            date: Date(timeIntervalSince1970: 100),
            memo: "Already imported",
            postings: [
                Posting(accountID: fixture.bank.id, money: Money(Decimal(-12), currency: fixture.eur)),
                Posting(accountID: fixture.uncategorized.id, money: Money(Decimal(12), currency: fixture.eur))
            ],
            state: .finalized,
            origin: origin
        )
        try ledger.addTransaction(existing)

        let line = fixture.line(description: "RIMI EESTI", externalID: "X1")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: ledger,
            classifier: classifier,
            now: fixture.now
        )

        XCTAssertEqual(
            preview.outcomes,
            [.skippedDuplicate(line: line, origin: origin, existingTransactionID: existing.id)]
        )
    }

    func testFailedOutcomesAreNotClassified() throws {
        let fixture = makeFixture()
        let missingAccountID = AccountID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: fixture.bank.id,
            defaultCounterpartyAccountID: missingAccountID
        )
        let line = fixture.line(description: "RIMI EESTI")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        ])

        let preview = pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        XCTAssertEqual(preview.outcomes, [.failed(line: line, error: .unknownAccount(missingAccountID))])
    }

    func testClassificationFailureConvertsProposedOutcomeToFailedOutcome() throws {
        let fixture = makeFixture()
        let foodID = fixture.food.id
        let transportID = fixture.transport.id
        let bankID = fixture.bank.id
        let eur = fixture.eur

        var pipeline = fixture.pipeline
        pipeline.addRule(
            ImportRule(name: "CreateSplit", applies: { _ in true }) { _, tx in
                tx.postings = [
                    Posting(accountID: bankID, money: Money(Decimal(-12), currency: eur)),
                    Posting(accountID: foodID, money: Money(Decimal(5), currency: eur)),
                    Posting(accountID: transportID, money: Money(Decimal(7), currency: eur))
                ]
            }
        )

        let line = fixture.line(description: "SPLIT RIMI")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("rimi", counterpartyAccountID: fixture.groceries.id)
        ])

        let preview = pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        XCTAssertEqual(
            preview.outcomes,
            [.failed(line: line, error: .classificationFailed(.ambiguousCounterpartyPostings))]
        )
    }

    func testCategoryRuleClassifiesFeeBearingOutgoingLineWithoutChangingFeePosting() throws {
        let fixture = makeFixture()
        let pipeline = fixture.pipelineWithFees
        let line = fixture.line(
            description: "RIMI EESTI",
            amount: Decimal(-12),
            fee: Decimal(string: "0.50")
        )
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("rimi", counterpartyAccountID: fixture.groceries.id)
        ])

        let preview = pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, _) = preview.outcomes.first else {
            return XCTFail("Expected fee-bearing line to remain importable")
        }

        XCTAssertEqual(draft.postings.map(\.role), [.statement, .counterparty, .fee])
        XCTAssertEqual(draft.postings[1].accountID, fixture.groceries.id)
        XCTAssertEqual(draft.postings[1].money.amount, Decimal(12))
        XCTAssertEqual(draft.postings[2].accountID, fixture.fees.id)
        XCTAssertEqual(draft.postings[2].money.amount, Decimal(string: "0.50"))
    }

    func testCategoryRuleClassifiesFeeBearingInflowWithoutChangingFeePosting() throws {
        let fixture = makeFixture()
        let pipeline = fixture.pipelineWithFees
        let line = fixture.line(
            description: "SALARY ACME",
            amount: Decimal(100),
            fee: Decimal(string: "0.50")
        )
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("salary", counterpartyAccountID: fixture.salary.id)
        ])

        let preview = pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, _) = preview.outcomes.first else {
            return XCTFail("Expected fee-bearing inflow to remain importable")
        }

        XCTAssertEqual(draft.postings.map(\.role), [.statement, .counterparty, .fee])
        XCTAssertEqual(draft.postings[0].money.amount, Decimal(string: "99.50"))
        XCTAssertEqual(draft.postings[1].accountID, fixture.salary.id)
        XCTAssertEqual(draft.postings[1].money.amount, Decimal(-100))
        XCTAssertEqual(draft.postings[2].accountID, fixture.fees.id)
    }

    func testClassifierTargetCurrencyMismatchFailsDuringPreview() throws {
        let fixture = makeFixture()
        let line = fixture.line(description: "RIMI EESTI")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("rimi", counterpartyAccountID: fixture.usdCategory.id)
        ])

        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        XCTAssertEqual(
            preview.outcomes,
            [
                .failed(
                    line: line,
                    error: .currencyMismatch(
                        fixture.usdCategory.id,
                        expected: fixture.usd,
                        actual: fixture.eur
                    )
                )
            ]
        )
    }

    func testClassifiedPreviewDoesNotMutateLedger() throws {
        let fixture = makeFixture()
        let before = fixture.ledger
        let line = fixture.line(description: "RIMI EESTI")
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("rimi", counterpartyAccountID: fixture.groceries.id)
        ])

        _ = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        XCTAssertEqual(fixture.ledger, before)
    }

    private func makeFixture() -> ImportClassificationFixture {
        ImportClassificationFixture()
    }
}

private struct ImportClassificationFixture {
    let eur: Currency
    let usd: Currency
    let ledger: Ledger
    let bank: Account
    let uncategorized: Account
    let groceries: Account
    let food: Account
    let transport: Account
    let fees: Account
    let salary: Account
    let usdCategory: Account
    let pipeline: ImportPipeline
    let now: Date

    init() {
        let eur = Currency("EUR")
        let usd = Currency("USD")
        let bank = Account(name: "Swedbank", kind: .asset)
        let uncategorized = Account(name: "Uncategorized", kind: .clearing)
        let groceries = Account(name: "Groceries", kind: .expense)
        let food = Account(name: "Food Delivery", kind: .expense)
        let transport = Account(name: "Transport", kind: .expense)
        let fees = Account(name: "Bank fees", kind: .expense)
        let salary = Account(name: "Salary", kind: .income)
        let usdCategory = Account(name: "US expenses", kind: .expense, currency: usd)
        let now = Date(timeIntervalSince1970: 123_456)

        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)
        ledger.addAccount(groceries)
        ledger.addAccount(food)
        ledger.addAccount(transport)
        ledger.addAccount(fees)
        ledger.addAccount(salary)
        ledger.addAccount(usdCategory)

        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )

        self.eur = eur
        self.usd = usd
        self.ledger = ledger
        self.bank = bank
        self.uncategorized = uncategorized
        self.groceries = groceries
        self.food = food
        self.transport = transport
        self.fees = fees
        self.salary = salary
        self.usdCategory = usdCategory
        self.pipeline = pipeline
        self.now = now
    }

    func line(
        description: String,
        externalID: String? = "X1",
        amount: Decimal = Decimal(-12),
        fee: Decimal? = nil
    ) -> BankLine {
        BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: amount,
            currency: eur,
            description: description,
            externalID: externalID,
            fee: fee
        )
    }

    var pipelineWithFees: ImportPipeline {
        ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id,
            feeAccountID: fees.id
        )
    }
}
