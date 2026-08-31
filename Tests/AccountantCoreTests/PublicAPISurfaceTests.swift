// Deliberately NOT @testable.
//
// Every other test file uses `@testable import`, which sees `internal` symbols.
// That makes a missing `public` invisible here and fatal in the app: the whole
// suite passes, then the iOS target fails with "cannot find type X in scope".
//
// This file imports the module the way a real consumer does, so anything it
// touches is guaranteed to be genuinely public. Add to it when the app starts
// depending on new core API.
import XCTest
import AccountantCore

final class PublicAPISurfaceTests: XCTestCase {

    private let eur = Currency("EUR")

    func testLedgerAndAccountingTypesArePublic() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur, sortOrder: 1)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(30), currency: eur),
            date: Date(timeIntervalSince1970: 100),
            memo: "Rimi"
        )

        try ledger.addTransaction(tx)
        try ledger.finalizeTransaction(id: tx.id)

        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(-30))
        XCTAssertFalse(ledger.statement(for: bank.id, currency: eur).isEmpty)
        XCTAssertTrue(ledger.draftTransactions().isEmpty)
    }

    func testReviewAndClearingAPIsArePublic() throws {
        var ledger = Ledger()

        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(10), currency: eur),
            date: Date(timeIntervalSince1970: 100)
        )
        try ledger.addTransaction(tx)

        XCTAssertEqual(try ledger.finalizeTransactions(ids: [tx.id]), 1)
        XCTAssertEqual(try ledger.setCleared(true, forAccount: bank.id, in: tx.id), 1)

        let report: ReconciliationReport = try ledger.reconcileAccount(
            bank.id,
            statementBalance: Money(Decimal(-10), currency: eur),
            asOf: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.clearedBalance.amount, Decimal(-10))
        XCTAssertEqual(report.clearedDifference.amount, .zero)

        let uncleared: [UnclearedEntry] = report.uncleared
        XCTAssertTrue(uncleared.isEmpty)
    }

    func testBudgetAPIIsPublic() throws {
        var ledger = Ledger()

        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let period = BudgetPeriod.containing(Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertGreaterThan(period.next, period)
        XCTAssertNotNil(period.dateInterval())

        var budget = Budget()
        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: groceries.id,
            from: period,
            in: ledger
        )

        let target: BudgetTarget? = budget.target(for: groceries.id, in: period)
        XCTAssertEqual(target?.amount.amount, Decimal(300))
        XCTAssertEqual(budget.targets(in: period).count, 1)
        XCTAssertTrue(budget.budgetedAccountIDs.contains(groceries.id))

        let report: BudgetReport = ledger.budgetReport(
            budget: budget,
            period: period,
            currency: eur
        )

        let lines: [BudgetLine] = report.lines
        let unbudgeted: [UnbudgetedLine] = report.unbudgeted

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(unbudgeted.isEmpty)
        XCTAssertEqual(report.totalTarget.amount, Decimal(300))
        XCTAssertEqual(report.totalRemaining.amount, Decimal(300))
        XCTAssertTrue(report.isWithinBudget)
        XCTAssertFalse(lines[0].isOverspent)
        XCTAssertNil(lines[0].overspend)
        XCTAssertEqual(lines[0].progress, 0)

        budget.removeTarget(for: groceries.id, from: period.next)
        budget.forget(accountID: groceries.id)

        XCTAssertTrue(AccountKind.expense.isBudgetable)
        XCTAssertFalse(AccountKind.asset.isBudgetable)
    }

    func testImportAndParsingAPIsArePublic() throws {
        let parser = CSVBankLineParser(source: "Swedbank")

        let result: BankLineParseResult = try parser.parseLines("""
        date,amount,currency,description,external_id
        2026-01-05,-12.50,EUR,RIMI,A-1
        """)

        XCTAssertEqual(result.lines.count, 1)
        XCTAssertFalse(result.hasRowErrors)

        let rowErrors: [BankLineRowError] = result.rowErrors
        XCTAssertTrue(rowErrors.isEmpty)
    }

    /// The export screen lives in the app target, so every symbol it touches has
    /// to be genuinely public — not merely visible through `@testable`.
    func testExportAndBackupAPIsArePublic() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        try ledger.addTransaction(
            try Transaction.draftExpense(
                paidFrom: bank.id,
                category: groceries.id,
                amount: Money(Decimal(12), currency: eur),
                date: Date(timeIntervalSince1970: 100),
                memo: "Rimi"
            )
        )

        let transactions: String = LedgerExport.transactionsCSV(
            from: ledger,
            includeDrafts: true,
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertTrue(transactions.contains("Swedbank"))

        let accounts: String = LedgerExport.accountsCSV(from: ledger, includeDrafts: true)
        XCTAssertTrue(accounts.contains("Groceries"))

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONLedgerStore(fileURL: directory.appendingPathComponent("ledger.json"))
        let backup: Data = try store.encoded(ledger)
        XCTAssertFalse(backup.isEmpty)
    }
}
