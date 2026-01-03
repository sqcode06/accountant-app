import XCTest
@testable import AccountantCore

final class PersistenceAndQueryTests: XCTestCase {

    func testSaveLoadRoundTrip() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let cash = Account(name: "Cash")
        let bank = Account(name: "Bank")
        ledger.addAccount(cash)
        ledger.addAccount(bank)

        let tx = Transaction(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            memo: "Transfer",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: bank.id, money: Money(Decimal(10), currency: eur))
            ]
        )
        try ledger.addTransaction(tx)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("ledger.json")

        let store = JSONLedgerStore(fileURL: fileURL)
        try store.save(ledger)

        let loaded = try store.load()
        XCTAssertEqual(loaded, ledger)
        XCTAssertEqual(loaded.balance(of: bank.id, currency: eur).amount, Decimal(10))
    }

    func testStatementRunningBalance() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let cash = Account(name: "Cash")
        ledger.addAccount(cash)

        // We'll add a "counterparty" account so transactions validate (>=2 postings).
        let contra = Account(name: "Contra")
        ledger.addAccount(contra)

        let t1 = Transaction(
            date: Date(timeIntervalSince1970: 10),
            memo: "Income",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(100), currency: eur)),
                Posting(accountID: contra.id, money: Money(Decimal(-100), currency: eur))
            ]
        )
        let t2 = Transaction(
            date: Date(timeIntervalSince1970: 20),
            memo: "Expense",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(-30), currency: eur)),
                Posting(accountID: contra.id, money: Money(Decimal(30), currency: eur))
            ]
        )

        try ledger.addTransaction(t1)
        try ledger.addTransaction(t2)

        let statement = ledger.statement(for: cash.id, currency: eur)
        XCTAssertEqual(statement.count, 2)
        XCTAssertEqual(statement[0].balance.amount, Decimal(100))
        XCTAssertEqual(statement[1].balance.amount, Decimal(70))
    }
}
