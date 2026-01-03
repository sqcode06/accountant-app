import XCTest
@testable import AccountantCore

final class AccountantCoreTests: XCTestCase {
    func testTransferIsBalancedAndAffectsBalances() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let cash = Account(name: "Cash")
        let bank = Account(name: "Bank")

        ledger.addAccount(cash)
        ledger.addAccount(bank)

        let tx = Transaction(
            memo: "Top up bank",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(-50), currency: eur)),
                Posting(accountID: bank.id, money: Money(Decimal(50), currency: eur)),
            ]
        )

        try ledger.addTransaction(tx)

        XCTAssertEqual(ledger.balance(of: cash.id, currency: eur).amount, Decimal(-50))
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(50))
    }

    func testUnbalancedTransactionThrows() {
        let eur = Currency("EUR")

        let tx = Transaction(postings: [
            Posting(accountID: AccountID(), money: Money(Decimal(10), currency: eur)),
            Posting(accountID: AccountID(), money: Money(Decimal(5), currency: eur)),
        ])

        XCTAssertThrowsError(try tx.validate())
    }
}
