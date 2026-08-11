import XCTest
@testable import AccountantCore

/// Administrative resets. These intentionally break rules that hold everywhere
/// else, so the boundaries matter more than usual.
final class DestructiveResetTests: XCTestCase {

    private let eur = Currency("EUR")

    private struct Fixture {
        var ledger: Ledger
        let bank: Account
        let groceries: Account
        let unused: Account
    }

    private func makeFixture() throws -> Fixture {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        let unused = Account(name: "Never used", kind: .expense)

        for account in [bank, groceries, unused] {
            ledger.addAccount(account)
        }

        let draft = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(10), currency: eur),
            date: Date(timeIntervalSince1970: 100)
        )
        let finalized = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(20), currency: eur),
            date: Date(timeIntervalSince1970: 200)
        )

        try ledger.addTransaction(draft)
        try ledger.addTransaction(finalized)
        try ledger.finalizeTransaction(id: finalized.id)

        return Fixture(ledger: ledger, bank: bank, groceries: groceries, unused: unused)
    }

    // MARK: - Clearing transactions

    func testRemovingAllTransactionsClearsFinalizedOnesToo() throws {
        var fixture = try makeFixture()

        XCTAssertTrue(fixture.ledger.transactions.contains { $0.state == .finalized })

        fixture.ledger.removeAllTransactions()

        // The whole point: this reaches past the immutability rule that
        // deleteDraftTransaction enforces.
        XCTAssertTrue(fixture.ledger.transactions.isEmpty)
        XCTAssertEqual(fixture.ledger.balance(of: fixture.bank.id, currency: eur).amount, .zero)
    }

    func testRemovingAllTransactionsKeepsAccounts() throws {
        var fixture = try makeFixture()
        let accountsBefore = fixture.ledger.accounts

        fixture.ledger.removeAllTransactions()

        XCTAssertEqual(fixture.ledger.accounts, accountsBefore)
    }

    func testLedgerStaysUsableAfterClearing() throws {
        var fixture = try makeFixture()
        fixture.ledger.removeAllTransactions()

        // Not just emptied — still a working ledger.
        let fresh = try Transaction.draftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: Money(Decimal(5), currency: eur),
            date: Date(timeIntervalSince1970: 300)
        )
        try fixture.ledger.addTransaction(fresh)
        try fixture.ledger.finalizeTransaction(id: fresh.id)

        XCTAssertEqual(fixture.ledger.balance(of: fixture.bank.id, currency: eur).amount, Decimal(-5))
    }

    func testClearingAnEmptyLedgerIsHarmless() {
        var ledger = Ledger()
        ledger.removeAllTransactions()

        XCTAssertTrue(ledger.transactions.isEmpty)
    }

    // MARK: - Removing unused accounts

    func testOnlyNeverUsedAccountsAreRemoved() throws {
        var fixture = try makeFixture()

        let removed = fixture.ledger.removeUnusedAccounts()

        XCTAssertEqual(removed.map(\.id), [fixture.unused.id])
        XCTAssertNil(fixture.ledger.accounts[fixture.unused.id])

        // Referenced accounts survive: deleting them would strand postings
        // pointing at nothing, which no invariant could repair.
        XCTAssertNotNil(fixture.ledger.accounts[fixture.bank.id])
        XCTAssertNotNil(fixture.ledger.accounts[fixture.groceries.id])
    }

    func testAccountsReferencedOnlyByADraftAreStillProtected() throws {
        var ledger = Ledger()

        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let category = Account(name: "Category", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(category)

        let draft = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: category.id,
            amount: Money(Decimal(10), currency: eur),
            date: Date(timeIntervalSince1970: 100)
        )
        try ledger.addTransaction(draft)

        XCTAssertTrue(ledger.removeUnusedAccounts().isEmpty)
        XCTAssertEqual(ledger.accounts.count, 2)
    }

    func testClearingThenPruningRemovesEverything() throws {
        var fixture = try makeFixture()

        fixture.ledger.removeAllTransactions()
        fixture.ledger.removeUnusedAccounts()

        // Once transactions are gone nothing is referenced, so a full reset is
        // reachable by composing the two.
        XCTAssertTrue(fixture.ledger.accounts.isEmpty)
        XCTAssertEqual(fixture.ledger, Ledger())
    }

    func testRemovalIsDeterministicallyOrdered() throws {
        var ledger = Ledger()

        for index in 0..<5 {
            ledger.addAccount(Account(name: "Spare \(index)", kind: .expense))
        }

        let removed = ledger.removeUnusedAccounts()
        let sorted = removed.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }

        XCTAssertEqual(removed.map(\.id), sorted.map(\.id))
    }
}
