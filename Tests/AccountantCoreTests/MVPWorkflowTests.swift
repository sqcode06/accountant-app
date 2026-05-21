import XCTest
@testable import AccountantCore

final class MVPWorkflowTests: XCTestCase {
    func testImportClassifyApplyFinalizeAndReconcileWorkflow() throws {
        let eur = Currency("EUR")

        let bank = Account(name: "Swedbank", kind: .asset)
        let uncategorized = Account(name: "Uncategorized", kind: .clearing)
        let salary = Account(name: "Salary", kind: .income)
        let groceries = Account(name: "Groceries", kind: .expense)
        let foodDelivery = Account(name: "Food Delivery", kind: .expense)

        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)
        ledger.addAccount(salary)
        ledger.addAccount(groceries)
        ledger.addAccount(foodDelivery)

        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )

        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "salary",
                counterpartyAccountID: salary.id,
                cleanedMemo: "Salary"
            ),
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: groceries.id,
                cleanedMemo: "Rimi"
            ),
            DescriptionContainsRule(
                "bolt food",
                counterpartyAccountID: foodDelivery.id,
                cleanedMemo: "Bolt Food"
            )
        ])

        let lines = [
            BankLine(
                date: Date(timeIntervalSince1970: 100),
                amount: Decimal(1000),
                currency: eur,
                description: "MAY SALARY",
                externalID: "SAL-001"
            ),
            BankLine(
                date: Date(timeIntervalSince1970: 110),
                amount: Decimal(-42),
                currency: eur,
                description: "RIMI EESTI",
                externalID: "RIMI-001"
            ),
            BankLine(
                date: Date(timeIntervalSince1970: 120),
                amount: Decimal(-18),
                currency: eur,
                description: "BOLT FOOD TALLINN",
                externalID: nil
            )
        ]

        let importNow = Date(timeIntervalSince1970: 1_000)
        let preview = pipeline.previewImport(
            lines: lines,
            into: ledger,
            classifier: classifier,
            now: importNow
        )

        XCTAssertEqual(preview.source, "Swedbank")
        XCTAssertEqual(preview.outcomes.count, 3)

        let proposed = try proposedOutcomes(from: preview)
        XCTAssertEqual(proposed.count, 3)

        XCTAssertEqual(proposed[0].line, lines[0])
        XCTAssertEqual(proposed[0].warnings, [])
        XCTAssertEqual(proposed[0].draft.memo, "Salary")
        XCTAssertEqual(proposed[0].draft.origin, TransactionOrigin(source: "Swedbank", externalID: "SAL-001"))
        XCTAssertEqual(proposed[0].draft.postings[0], Posting(accountID: bank.id, money: Money(Decimal(1000), currency: eur)))
        XCTAssertEqual(proposed[0].draft.postings[1], Posting(accountID: salary.id, money: Money(Decimal(-1000), currency: eur)))

        XCTAssertEqual(proposed[1].line, lines[1])
        XCTAssertEqual(proposed[1].warnings, [])
        XCTAssertEqual(proposed[1].draft.memo, "Rimi")
        XCTAssertEqual(proposed[1].draft.origin, TransactionOrigin(source: "Swedbank", externalID: "RIMI-001"))
        XCTAssertEqual(proposed[1].draft.postings[0], Posting(accountID: bank.id, money: Money(Decimal(-42), currency: eur)))
        XCTAssertEqual(proposed[1].draft.postings[1], Posting(accountID: groceries.id, money: Money(Decimal(42), currency: eur)))

        XCTAssertEqual(proposed[2].line, lines[2])
        XCTAssertEqual(proposed[2].warnings, [.missingExternalID])
        XCTAssertEqual(proposed[2].draft.memo, "Bolt Food")
        XCTAssertNil(proposed[2].draft.origin)
        XCTAssertEqual(proposed[2].draft.postings[0], Posting(accountID: bank.id, money: Money(Decimal(-18), currency: eur)))
        XCTAssertEqual(proposed[2].draft.postings[1], Posting(accountID: foodDelivery.id, money: Money(Decimal(18), currency: eur)))

        let applyReport = try pipeline.applyImportPreview(preview, to: &ledger)
        XCTAssertEqual(applyReport.insertedTransactions, 3)
        XCTAssertEqual(applyReport.skippedOutcomes, 0)
        XCTAssertEqual(ledger.transactions.count, 3)
        XCTAssertTrue(ledger.transactions.allSatisfy { $0.state == .draft })

        let finalizeNow = Date(timeIntervalSince1970: 2_000)
        for id in ledger.transactions.map(\.id) {
            try ledger.finalizeTransaction(id: id, now: finalizeNow)
        }

        let finalized = ledger.allTransactionsSorted(includeDrafts: false)
        XCTAssertEqual(finalized.count, 3)
        XCTAssertTrue(finalized.allSatisfy { $0.state == .finalized })
        XCTAssertEqual(finalized.map(\.memo), ["Salary", "Rimi", "Bolt Food"])
        XCTAssertEqual(finalized.map(\.updatedAt), [finalizeNow, finalizeNow, finalizeNow])

        let asOf = Date(timeIntervalSince1970: 200)
        let reconciliation = try ledger.reconcileAccount(
            bank.id,
            statementBalance: Money(Decimal(940), currency: eur),
            asOf: asOf
        )

        XCTAssertEqual(reconciliation.status, .matched)
        XCTAssertEqual(reconciliation.ledgerBalance, Money(Decimal(940), currency: eur))
        XCTAssertEqual(reconciliation.statementBalance, Money(Decimal(940), currency: eur))
        XCTAssertEqual(reconciliation.difference, Money(Decimal(0), currency: eur))
        XCTAssertFalse(reconciliation.includeDrafts)

        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur, asOf: asOf, includeDrafts: false), Money(Decimal(940), currency: eur))
        XCTAssertEqual(ledger.balance(of: salary.id, currency: eur), Money(Decimal(-1000), currency: eur))
        XCTAssertEqual(ledger.balance(of: groceries.id, currency: eur), Money(Decimal(42), currency: eur))
        XCTAssertEqual(ledger.balance(of: foodDelivery.id, currency: eur), Money(Decimal(18), currency: eur))
        XCTAssertEqual(ledger.balance(of: uncategorized.id, currency: eur), Money(Decimal(0), currency: eur))
    }

    private func proposedOutcomes(
        from preview: ImportPreview,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [(line: BankLine, draft: Transaction, warnings: [ImportWarning])] {
        try preview.outcomes.map { outcome in
            guard case .proposed(let line, let draft, let warnings) = outcome else {
                XCTFail("Expected all outcomes to be proposed, got: \(outcome)", file: file, line: line)
                throw MVPWorkflowTestError.unexpectedImportOutcome
            }

            return (line, draft, warnings)
        }
    }
}

private enum MVPWorkflowTestError: Error {
    case unexpectedImportOutcome
}