import XCTest
@testable import AccountantCore

final class ReconciliationTests: XCTestCase {
    func testReconcileMatchesFinalizedBalanceByDefault() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "Salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        try ledger.addTransaction(
            Transaction.draft(
                date: Date(timeIntervalSince1970: 110),
                memo: "Draft groceries",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(-40), currency: fixture.eur)),
                    Posting(accountID: fixture.expense.id, money: Money(Decimal(40), currency: fixture.eur))
                ]
            )
        )

        let report = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(100), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(report.accountID, fixture.bank.id)
        XCTAssertEqual(report.currency, fixture.eur)
        XCTAssertEqual(report.asOf, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(report.ledgerBalance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(report.statementBalance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(report.difference, Money(Decimal(0), currency: fixture.eur))
        XCTAssertEqual(report.status, .matched)
        XCTAssertFalse(report.includeDrafts)
    }

    func testReconcileCanIncludeDraftTransactions() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "Salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        try ledger.addTransaction(
            Transaction.draft(
                date: Date(timeIntervalSince1970: 110),
                memo: "Draft groceries",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(-40), currency: fixture.eur)),
                    Posting(accountID: fixture.expense.id, money: Money(Decimal(40), currency: fixture.eur))
                ]
            )
        )

        let report = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(60), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200),
            includeDrafts: true
        )

        XCTAssertEqual(report.ledgerBalance, Money(Decimal(60), currency: fixture.eur))
        XCTAssertEqual(report.difference, Money(Decimal(0), currency: fixture.eur))
        XCTAssertEqual(report.status, .matched)
        XCTAssertTrue(report.includeDrafts)
    }

    func testMismatchedReportReturnsStatementMinusLedgerDifference() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "Salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        let report = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(80), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(report.ledgerBalance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(report.statementBalance, Money(Decimal(80), currency: fixture.eur))
        XCTAssertEqual(report.difference, Money(Decimal(-20), currency: fixture.eur))
        XCTAssertEqual(report.status, .mismatched)
    }

    func testReconcileAsOfIgnoresLaterTransactions() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "Salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 300),
                memo: "Later expense",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(-25), currency: fixture.eur)),
                    Posting(accountID: fixture.expense.id, money: Money(Decimal(25), currency: fixture.eur))
                ]
            )
        )

        let report = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(100), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(report.ledgerBalance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(report.status, .matched)
    }

    func testReconcileThrowsDedicatedErrorForUnknownAccount() throws {
        let eur = Currency("EUR")
        let missingAccountID = AccountID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let ledger = Ledger()

        XCTAssertThrowsError(
            try ledger.reconcileAccount(
                missingAccountID,
                statementBalance: Money(Decimal(0), currency: eur),
                asOf: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? ReconciliationError, .unknownAccount(missingAccountID))
        }
    }

    func testArchivedAccountCanStillBeReconciled() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "Salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        try ledger.archiveAccount(id: fixture.bank.id)

        let report = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(100), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(report.ledgerBalance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(report.status, .matched)
    }

    func testReconcileUsesStatementCurrencyOnly() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "EUR salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "USD salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(50), currency: fixture.usd)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-50), currency: fixture.usd))
                ]
            )
        )

        let eurReport = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(100), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200)
        )

        let usdReport = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(50), currency: fixture.usd),
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(eurReport.ledgerBalance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(eurReport.status, .matched)
        XCTAssertEqual(usdReport.ledgerBalance, Money(Decimal(50), currency: fixture.usd))
        XCTAssertEqual(usdReport.status, .matched)
    }

    func testReconciliationDoesNotMutateLedger() throws {
        let fixture = makeFixture()
        var ledger = fixture.ledger

        try ledger.addTransaction(
            Transaction.finalized(
                date: Date(timeIntervalSince1970: 100),
                memo: "Salary",
                postings: [
                    Posting(accountID: fixture.bank.id, money: Money(Decimal(100), currency: fixture.eur)),
                    Posting(accountID: fixture.income.id, money: Money(Decimal(-100), currency: fixture.eur))
                ]
            )
        )

        let before = ledger

        _ = try ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(Decimal(100), currency: fixture.eur),
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(ledger, before)
    }

    private func makeFixture() -> (
        eur: Currency,
        usd: Currency,
        ledger: Ledger,
        bank: Account,
        income: Account,
        expense: Account
    ) {
        let eur = Currency("EUR")
        let usd = Currency("USD")
        let bank = Account(name: "Bank", kind: .asset)
        let income = Account(name: "Salary", kind: .income)
        let expense = Account(name: "Groceries", kind: .expense)

        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(income)
        ledger.addAccount(expense)

        return (eur, usd, ledger, bank, income, expense)
    }
}
