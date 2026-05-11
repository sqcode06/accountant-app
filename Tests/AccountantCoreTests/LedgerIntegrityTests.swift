import XCTest
@testable import AccountantCore

final class LedgerIntegrityTests: XCTestCase {

    func testAddingTransactionWithDuplicateIDThrowsAndDoesNotMutateLedger() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let cash = Account(name: "Cash")
        let bank = Account(name: "Bank")

        ledger.addAccount(cash)
        ledger.addAccount(bank)

        let id = TransactionID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)

        let original = Transaction(
            id: id,
            date: Date(timeIntervalSince1970: 100),
            memo: "Original",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: bank.id, money: Money(Decimal(10), currency: eur))
            ]
        )

        let duplicate = Transaction(
            id: id,
            date: Date(timeIntervalSince1970: 200),
            memo: "Duplicate",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(-999), currency: eur)),
                Posting(accountID: bank.id, money: Money(Decimal(999), currency: eur))
            ]
        )

        try ledger.addTransaction(original)

        XCTAssertThrowsError(try ledger.addTransaction(duplicate)) { error in
            XCTAssertEqual(error as? LedgerError, LedgerError.duplicateTransactionID(id))
        }

        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.transactions.first?.memo, "Original")
        XCTAssertEqual(ledger.balance(of: cash.id, currency: eur).amount, Decimal(-10))
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(10))
    }
}