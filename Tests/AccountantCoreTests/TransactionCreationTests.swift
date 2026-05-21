import XCTest
@testable import AccountantCore

final class TransactionCreationTests: XCTestCase {
    func testDraftExpenseCreatesBalancedDraftWithExpectedPostings() throws {
        let eur = Currency("EUR")
        let bank = AccountID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let groceries = AccountID(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        let date = Date(timeIntervalSince1970: 100)
        let origin = TransactionOrigin(source: "manual", externalID: "expense-1")

        let tx = try Transaction.draftExpense(
            paidFrom: bank,
            category: groceries,
            amount: Money(Decimal(42), currency: eur),
            date: date,
            memo: "Rimi",
            origin: origin
        )

        XCTAssertEqual(tx.state, .draft)
        XCTAssertEqual(tx.date, date)
        XCTAssertEqual(tx.memo, "Rimi")
        XCTAssertEqual(tx.origin, origin)
        XCTAssertEqual(tx.postings, [
            Posting(accountID: bank, money: Money(Decimal(-42), currency: eur)),
            Posting(accountID: groceries, money: Money(Decimal(42), currency: eur))
        ])

        try tx.validate()
    }

    func testDraftIncomeCreatesBalancedDraftWithExpectedPostings() throws {
        let eur = Currency("EUR")
        let bank = AccountID(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)
        let salary = AccountID(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!)
        let date = Date(timeIntervalSince1970: 200)

        let tx = try Transaction.draftIncome(
            receivedIn: bank,
            source: salary,
            amount: Money(Decimal(1000), currency: eur),
            date: date,
            memo: "Salary"
        )

        XCTAssertEqual(tx.state, .draft)
        XCTAssertEqual(tx.date, date)
        XCTAssertEqual(tx.memo, "Salary")
        XCTAssertNil(tx.origin)
        XCTAssertEqual(tx.postings, [
            Posting(accountID: bank, money: Money(Decimal(1000), currency: eur)),
            Posting(accountID: salary, money: Money(Decimal(-1000), currency: eur))
        ])

        try tx.validate()
    }

    func testDraftTransferCreatesBalancedDraftWithExpectedPostings() throws {
        let eur = Currency("EUR")
        let checking = AccountID(UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!)
        let savings = AccountID(UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!)
        let date = Date(timeIntervalSince1970: 300)

        let tx = try Transaction.draftTransfer(
            from: checking,
            to: savings,
            amount: Money(Decimal(250), currency: eur),
            date: date,
            memo: "Move to savings"
        )

        XCTAssertEqual(tx.state, .draft)
        XCTAssertEqual(tx.date, date)
        XCTAssertEqual(tx.memo, "Move to savings")
        XCTAssertEqual(tx.postings, [
            Posting(accountID: checking, money: Money(Decimal(-250), currency: eur)),
            Posting(accountID: savings, money: Money(Decimal(250), currency: eur))
        ])

        try tx.validate()
    }

    func testDraftConstructorsRejectZeroAmount() {
        let eur = Currency("EUR")
        let a = AccountID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let b = AccountID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let zero = Money(Decimal(0), currency: eur)

        XCTAssertThrowsError(
            try Transaction.draftExpense(paidFrom: a, category: b, amount: zero)
        ) { error in
            XCTAssertEqual(error as? TransactionCreationError, .nonPositiveAmount(zero))
        }

        XCTAssertThrowsError(
            try Transaction.draftIncome(receivedIn: a, source: b, amount: zero)
        ) { error in
            XCTAssertEqual(error as? TransactionCreationError, .nonPositiveAmount(zero))
        }

        XCTAssertThrowsError(
            try Transaction.draftTransfer(from: a, to: b, amount: zero)
        ) { error in
            XCTAssertEqual(error as? TransactionCreationError, .nonPositiveAmount(zero))
        }
    }

    func testDraftConstructorsRejectNegativeAmount() {
        let eur = Currency("EUR")
        let a = AccountID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        let b = AccountID(UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        let negative = Money(Decimal(-1), currency: eur)

        XCTAssertThrowsError(
            try Transaction.draftExpense(paidFrom: a, category: b, amount: negative)
        ) { error in
            XCTAssertEqual(error as? TransactionCreationError, .nonPositiveAmount(negative))
        }

        XCTAssertThrowsError(
            try Transaction.draftIncome(receivedIn: a, source: b, amount: negative)
        ) { error in
            XCTAssertEqual(error as? TransactionCreationError, .nonPositiveAmount(negative))
        }

        XCTAssertThrowsError(
            try Transaction.draftTransfer(from: a, to: b, amount: negative)
        ) { error in
            XCTAssertEqual(error as? TransactionCreationError, .nonPositiveAmount(negative))
        }
    }

    func testConstructedTransactionsCanBeAddedToLedger() throws {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)

        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(12), currency: eur),
            memo: "Groceries"
        )

        try ledger.addTransaction(tx)

        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur), Money(Decimal(-12), currency: eur))
        XCTAssertEqual(ledger.balance(of: groceries.id, currency: eur), Money(Decimal(12), currency: eur))
    }
}
