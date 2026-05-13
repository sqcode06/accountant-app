import XCTest
@testable import AccountantCore

final class ImportPipelineTests: XCTestCase {
    func testImportCreatesBalancedDrafts() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset)
        let uncategorizedAccount = Account(name: "Uncategorized", kind: .clearing)
        ledger.addAccount(bank)
        ledger.addAccount(uncategorizedAccount)

        let pipeline = ImportPipeline(source: "MyBank", statementAccountID: bank.id, defaultCounterpartyAccountID: uncategorizedAccount.id)

        let lines = [
            BankLine(date: Date(timeIntervalSince1970: 10), amount: Decimal(-5), currency: eur, description: "Coffee", externalID: "X1"),
            BankLine(date: Date(timeIntervalSince1970: 20), amount: Decimal(100), currency: eur, description: "Salary", externalID: "X2"),
        ]

        let drafts = try pipeline.makeDrafts(from: lines)

        for draft in drafts {
            XCTAssertEqual(draft.state, .draft)
            try draft.validate()
            try ledger.addTransaction(draft) // should not throw
        }

        XCTAssertEqual(ledger.transactions.count, 2)
    }

    func testExternalIDIsAttachedAsTransactionOrigin() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let uncategorized = Account(name: "Uncategorized", kind: .clearing)
        let pipeline = ImportPipeline(source: "Swedbank", statementAccountID: bank.id, defaultCounterpartyAccountID: uncategorized.id)

        let line = BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-12),
            currency: eur,
            description: "Lunch",
            externalID: "BANK-123"
        )

        let draft = try pipeline.makeDraft(from: line)

        XCTAssertEqual(draft.origin, TransactionOrigin(source: "Swedbank", externalID: "BANK-123"))
    }

    func testMissingExternalIDLeavesOriginNil() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let uncategorized = Account(name: "Uncategorized", kind: .clearing)
        let pipeline = ImportPipeline(source: "Swedbank", statementAccountID: bank.id, defaultCounterpartyAccountID: uncategorized.id)

        let line = BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-12),
            currency: eur,
            description: "Lunch",
            externalID: nil
        )

        let draft = try pipeline.makeDraft(from: line)

        XCTAssertNil(draft.origin)
    }

    func testOutgoingLineUsesStatementAmountAndOppositeCounterpartyAmount() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Groceries", kind: .expense)
        let pipeline = ImportPipeline(source: "Bank", statementAccountID: bank.id, defaultCounterpartyAccountID: expense.id)

        let line = BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-25),
            currency: eur,
            description: "Groceries",
            externalID: "OUT-1"
        )

        let draft = try pipeline.makeDraft(from: line)

        XCTAssertEqual(draft.postings.count, 2)
        XCTAssertEqual(draft.postings[0], Posting(accountID: bank.id, money: Money(Decimal(-25), currency: eur)))
        XCTAssertEqual(draft.postings[1], Posting(accountID: expense.id, money: Money(Decimal(25), currency: eur)))
    }

    func testIncomingLineUsesStatementAmountAndOppositeCounterpartyAmount() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let income = Account(name: "Salary", kind: .income)
        let pipeline = ImportPipeline(source: "Bank", statementAccountID: bank.id, defaultCounterpartyAccountID: income.id)

        let line = BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(1000),
            currency: eur,
            description: "Salary",
            externalID: "IN-1"
        )

        let draft = try pipeline.makeDraft(from: line)

        XCTAssertEqual(draft.postings.count, 2)
        XCTAssertEqual(draft.postings[0], Posting(accountID: bank.id, money: Money(Decimal(1000), currency: eur)))
        XCTAssertEqual(draft.postings[1], Posting(accountID: income.id, money: Money(Decimal(-1000), currency: eur)))
    }

    func testMatchingRulesApplyInInsertionOrder() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Expense", kind: .expense)

        var pipeline = ImportPipeline(source: "Bank", statementAccountID: bank.id, defaultCounterpartyAccountID: expense.id)
        pipeline.addRule(
            ImportRule(name: "First", applies: { _ in true }) { _, tx in
                tx.memo = "A"
            }
        )
        pipeline.addRule(
            ImportRule(name: "Second", applies: { _ in true }) { _, tx in
                tx.memo = (tx.memo ?? "") + "B"
            }
        )

        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-1), currency: eur, description: "Original", externalID: "X")

        let draft = try pipeline.makeDraft(from: line)

        XCTAssertEqual(draft.memo, "AB")
    }

    func testNonMatchingRulesDoNotApply() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Expense", kind: .expense)

        var pipeline = ImportPipeline(source: "Bank", statementAccountID: bank.id, defaultCounterpartyAccountID: expense.id)
        pipeline.addRule(
            ImportRule(name: "Never", applies: { _ in false }) { _, tx in
                tx.memo = "Should not happen"
            }
        )

        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-1), currency: eur, description: "Original", externalID: "X")

        let draft = try pipeline.makeDraft(from: line)

        XCTAssertEqual(draft.memo, "Original")
    }

    func testRuleCreatedInvalidTransactionThrowsValidationError() {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Expense", kind: .expense)

        var pipeline = ImportPipeline(source: "Bank", statementAccountID: bank.id, defaultCounterpartyAccountID: expense.id)
        pipeline.addRule(
            ImportRule(name: "BreakBalance", applies: { _ in true }) { _, tx in
                tx.postings = [
                    Posting(accountID: bank.id, money: Money(Decimal(-10), currency: eur)),
                    Posting(accountID: expense.id, money: Money(Decimal(9), currency: eur))
                ]
            }
        )

        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-10), currency: eur, description: "Broken", externalID: "X")

        XCTAssertThrowsError(try pipeline.makeDraft(from: line)) { error in
            XCTAssertEqual(error as? LedgerError, LedgerError.unbalancedTransaction(sum: Decimal(-1)))
        }
    }

    func testProvidedNowControlsUpdatedAt() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Expense", kind: .expense)
        let pipeline = ImportPipeline(source: "Bank", statementAccountID: bank.id, defaultCounterpartyAccountID: expense.id)
        let now = Date(timeIntervalSince1970: 12_345)

        let line = BankLine(date: Date(timeIntervalSince1970: 100), amount: Decimal(-1), currency: eur, description: "Timed", externalID: "X")

        let draft = try pipeline.makeDraft(from: line, now: now)

        XCTAssertEqual(draft.updatedAt, now)
    }
}
