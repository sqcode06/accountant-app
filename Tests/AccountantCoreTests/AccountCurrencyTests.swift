import XCTest
@testable import AccountantCore

/// Covers account currency denomination.
///
/// The behaviour these tests pin down is a real bug that existed before accounts
/// could declare a currency: a posting in the wrong currency was accepted by the
/// ledger, then filtered out by every balance query, so the amount silently
/// disappeared from the app without any error ever being raised.
final class AccountCurrencyTests: XCTestCase {

    private let eur = Currency("EUR")
    private let usd = Currency("USD")

    // MARK: - Rejection

    func testPostingInWrongCurrencyIsRejectedByDenominatedAccount() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let dollarSpend = Transaction(
            date: Date(timeIntervalSince1970: 100),
            memo: "Bought abroad",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-42), currency: usd)),
                Posting(accountID: groceries.id, money: Money(Decimal(42), currency: usd))
            ]
        )

        XCTAssertThrowsError(try ledger.addTransaction(dollarSpend)) { error in
            XCTAssertEqual(
                error as? LedgerError,
                LedgerError.accountCurrencyMismatch(bank.id, expected: self.eur, actual: self.usd)
            )
        }

        // The ledger must be untouched: this is the "money vanishes" case.
        XCTAssertTrue(ledger.transactions.isEmpty)
    }

    func testRejectedPostingWouldOtherwiseHaveVanishedFromBalances() throws {
        // Documents precisely why the check matters. An account with no declared
        // currency still accepts the USD posting, and the EUR balance then reports
        // zero — the transaction exists but is invisible to the app.
        var ledger = Ledger()

        let undenominated = Account(name: "Legacy Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(undenominated)
        ledger.addAccount(groceries)

        try ledger.addTransaction(
            Transaction(
                date: Date(timeIntervalSince1970: 100),
                postings: [
                    Posting(accountID: undenominated.id, money: Money(Decimal(-42), currency: usd)),
                    Posting(accountID: groceries.id, money: Money(Decimal(42), currency: usd))
                ]
            )
        )

        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.balance(of: undenominated.id, currency: eur).amount, Decimal.zero)
        XCTAssertEqual(ledger.balance(of: undenominated.id, currency: usd).amount, Decimal(-42))
    }

    // MARK: - Acceptance

    func testMatchingCurrencyIsAccepted() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        try ledger.addTransaction(
            try Transaction.draftExpense(
                paidFrom: bank.id,
                category: groceries.id,
                amount: Money(Decimal(42), currency: eur),
                date: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(-42))
    }

    func testUndenominatedCategoryAccountAcceptsMultipleCurrencies() throws {
        // Category accounts are deliberately currency-agnostic: groceries bought in
        // euros and groceries bought in dollars both belong in Groceries.
        var ledger = Ledger()

        let eurBank = Account(name: "EUR Bank", kind: .asset, currency: eur)
        let usdBank = Account(name: "USD Bank", kind: .asset, currency: usd)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(eurBank)
        ledger.addAccount(usdBank)
        ledger.addAccount(groceries)

        try ledger.addTransaction(
            try Transaction.draftExpense(
                paidFrom: eurBank.id,
                category: groceries.id,
                amount: Money(Decimal(10), currency: eur),
                date: Date(timeIntervalSince1970: 100)
            )
        )

        try ledger.addTransaction(
            try Transaction.draftExpense(
                paidFrom: usdBank.id,
                category: groceries.id,
                amount: Money(Decimal(20), currency: usd),
                date: Date(timeIntervalSince1970: 200)
            )
        )

        // Balances stay separated by currency. No implicit conversion anywhere.
        XCTAssertEqual(ledger.balance(of: groceries.id, currency: eur).amount, Decimal(10))
        XCTAssertEqual(ledger.balance(of: groceries.id, currency: usd).amount, Decimal(20))
    }

    // MARK: - Enforcement on edit

    func testEditingDraftIntoWrongCurrencyIsRejected() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let draft = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(42), currency: eur),
            date: Date(timeIntervalSince1970: 100)
        )
        try ledger.addTransaction(draft)

        XCTAssertThrowsError(
            try ledger.updateDraftTransaction(id: draft.id) { tx in
                tx.postings = [
                    Posting(accountID: bank.id, money: Money(Decimal(-42), currency: self.usd)),
                    Posting(accountID: groceries.id, money: Money(Decimal(42), currency: self.usd))
                ]
            }
        )

        // The original EUR draft must survive the rejected edit intact.
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(-42))
    }

    // MARK: - Persistence

    func testCurrencyAndNewAccountFieldsSurviveRoundTrip() throws {
        var ledger = Ledger()

        ledger.addAccount(
            Account(
                name: "Swedbank",
                kind: .asset,
                currency: eur,
                sortOrder: 3,
                symbolName: "building.columns",
                colorToken: "teal"
            )
        )

        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(Ledger.self, from: data)
        let account = try XCTUnwrap(decoded.accounts.values.first)

        XCTAssertEqual(account.currency, eur)
        XCTAssertEqual(account.sortOrder, 3)
        XCTAssertEqual(account.symbolName, "building.columns")
        XCTAssertEqual(account.colorToken, "teal")
    }

    func testAccountDecodesWhenNewFieldsAreAbsent() throws {
        // Ledgers written before these fields existed must still load.
        let json = """
        {
          "accounts": [
            { "id": { "rawValue": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" },
              "name": "Old Bank", "kind": "asset", "status": "active" }
          ],
          "transactions": []
        }
        """

        let decoded = try JSONDecoder().decode(Ledger.self, from: Data(json.utf8))
        let account = try XCTUnwrap(decoded.accounts.values.first)

        XCTAssertEqual(account.name, "Old Bank")
        XCTAssertNil(account.currency)
        XCTAssertEqual(account.sortOrder, 0)
        XCTAssertNil(account.symbolName)
    }
}
