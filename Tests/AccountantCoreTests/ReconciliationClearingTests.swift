import XCTest
@testable import AccountantCore

/// Covers the ticking workflow: reconciliation must be able to say *which*
/// transactions explain a difference, not merely that a difference exists.
final class ReconciliationClearingTests: XCTestCase {

    private let eur = Currency("EUR")

    private struct Fixture {
        var ledger: Ledger
        let bank: Account
        let groceries: Account
        let rent: Account
        let groceriesTx: TransactionID
        let rentTx: TransactionID
    }

    /// Bank starts empty, then two finalized expenses: -30 groceries, -500 rent.
    private func makeFixture() throws -> Fixture {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        let rent = Account(name: "Rent", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)
        ledger.addAccount(rent)

        let groceriesTx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(30), currency: eur),
            date: Date(timeIntervalSince1970: 100),
            memo: "Rimi"
        )
        let rentTx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: rent.id,
            amount: Money(Decimal(500), currency: eur),
            date: Date(timeIntervalSince1970: 200),
            memo: "August rent"
        )

        try ledger.addTransaction(groceriesTx)
        try ledger.addTransaction(rentTx)
        try ledger.finalizeTransaction(id: groceriesTx.id)
        try ledger.finalizeTransaction(id: rentTx.id)

        return Fixture(
            ledger: ledger,
            bank: bank,
            groceries: groceries,
            rent: rent,
            groceriesTx: groceriesTx.id,
            rentTx: rentTx.id
        )
    }

    private func report(
        _ fixture: Fixture,
        statement: Decimal
    ) throws -> ReconciliationReport {
        try fixture.ledger.reconcileAccount(
            fixture.bank.id,
            statementBalance: Money(statement, currency: eur),
            asOf: Date(timeIntervalSince1970: 1_000)
        )
    }

    // MARK: - Listing

    func testUnclearedEntriesAreListedOldestFirstWithTheirDeltas() throws {
        let fixture = try makeFixture()
        let report = try report(fixture, statement: Decimal(-530))

        XCTAssertEqual(report.uncleared.count, 2)
        XCTAssertEqual(report.uncleared[0].memo, "Rimi")
        XCTAssertEqual(report.uncleared[0].delta.amount, Decimal(-30))
        XCTAssertEqual(report.uncleared[1].memo, "August rent")
        XCTAssertEqual(report.uncleared[1].delta.amount, Decimal(-500))
    }

    func testNothingIsClearedInitially() throws {
        let fixture = try makeFixture()
        let report = try report(fixture, statement: Decimal(-530))

        XCTAssertEqual(report.ledgerBalance.amount, Decimal(-530))
        XCTAssertEqual(report.clearedBalance.amount, Decimal.zero)
        // Book agrees with the bank overall...
        XCTAssertEqual(report.difference.amount, Decimal.zero)
        XCTAssertEqual(report.status, .matched)
        // ...but nothing has actually been ticked off yet.
        XCTAssertEqual(report.clearedDifference.amount, Decimal(-530))
    }

    // MARK: - Ticking

    func testClearingEntriesMovesClearedBalanceTowardStatement() throws {
        var fixture = try makeFixture()

        try fixture.ledger.setCleared(true, forAccount: fixture.bank.id, in: fixture.groceriesTx)

        var current = try report(fixture, statement: Decimal(-530))
        XCTAssertEqual(current.clearedBalance.amount, Decimal(-30))
        XCTAssertEqual(current.clearedDifference.amount, Decimal(-500))
        XCTAssertEqual(current.uncleared.count, 1)
        XCTAssertEqual(current.uncleared.first?.memo, "August rent")

        try fixture.ledger.setCleared(true, forAccount: fixture.bank.id, in: fixture.rentTx)

        current = try report(fixture, statement: Decimal(-530))
        XCTAssertEqual(current.clearedBalance.amount, Decimal(-530))
        XCTAssertEqual(current.clearedDifference.amount, Decimal.zero)
        XCTAssertTrue(current.uncleared.isEmpty)
    }

    func testClearingIsAllowedOnFinalizedTransactions() throws {
        var fixture = try makeFixture()

        // Both fixture transactions are finalized; editing them would throw.
        XCTAssertThrowsError(
            try fixture.ledger.updateDraftTransaction(id: fixture.rentTx) { $0.memo = "nope" }
        )

        // Clearing records a bank confirmation rather than editing a fact, so it works.
        let changed = try fixture.ledger.setCleared(
            true,
            forAccount: fixture.bank.id,
            in: fixture.rentTx
        )
        XCTAssertEqual(changed, 1)
    }

    func testClearingOnlyAffectsTheNamedAccountsPostings() throws {
        var fixture = try makeFixture()

        try fixture.ledger.setCleared(true, forAccount: fixture.bank.id, in: fixture.groceriesTx)

        let tx = try XCTUnwrap(fixture.ledger.transactions.first { $0.id == fixture.groceriesTx })
        let bankPosting = try XCTUnwrap(tx.postings.first { $0.accountID == fixture.bank.id })
        let groceriesPosting = try XCTUnwrap(tx.postings.first { $0.accountID == fixture.groceries.id })

        XCTAssertTrue(bankPosting.cleared)
        XCTAssertFalse(groceriesPosting.cleared)
    }

    func testUnclearingReversesTheEffect() throws {
        var fixture = try makeFixture()

        try fixture.ledger.setCleared(true, forAccount: fixture.bank.id, in: fixture.groceriesTx)
        try fixture.ledger.setCleared(false, forAccount: fixture.bank.id, in: fixture.groceriesTx)

        let current = try report(fixture, statement: Decimal(-530))
        XCTAssertEqual(current.clearedBalance.amount, Decimal.zero)
        XCTAssertEqual(current.uncleared.count, 2)
    }

    func testRepeatedClearingReportsNoFurtherChange() throws {
        var fixture = try makeFixture()

        let first = try fixture.ledger.setCleared(
            true,
            forAccount: fixture.bank.id,
            in: fixture.groceriesTx
        )
        let second = try fixture.ledger.setCleared(
            true,
            forAccount: fixture.bank.id,
            in: fixture.groceriesTx
        )

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
    }

    // MARK: - The workflow this enables

    func testStatementMissingOneEntryLeavesExactlyThatEntryUncleared() throws {
        var fixture = try makeFixture()

        // The statement shows only the groceries; rent has not posted at the bank yet.
        try fixture.ledger.setCleared(true, forAccount: fixture.bank.id, in: fixture.groceriesTx)

        let current = try report(fixture, statement: Decimal(-30))

        // Ticking is complete against this statement.
        XCTAssertEqual(current.clearedDifference.amount, Decimal.zero)

        // And the leftover names the pending item rather than just a number.
        XCTAssertEqual(current.uncleared.count, 1)
        XCTAssertEqual(current.uncleared.first?.memo, "August rent")
        XCTAssertEqual(current.uncleared.first?.delta.amount, Decimal(-500))
    }

    // MARK: - Errors

    func testClearingUnknownTransactionThrows() throws {
        var fixture = try makeFixture()

        XCTAssertThrowsError(
            try fixture.ledger.setCleared(
                true,
                forAccount: fixture.bank.id,
                in: TransactionID()
            )
        )
    }

    func testClearingUnknownAccountThrows() throws {
        var fixture = try makeFixture()

        XCTAssertThrowsError(
            try fixture.ledger.setCleared(
                true,
                forAccount: AccountID(),
                in: fixture.groceriesTx
            )
        ) { error in
            XCTAssertEqual(error as? ReconciliationError != nil, true)
        }
    }

    // MARK: - Persistence

    func testClearedFlagSurvivesRoundTrip() throws {
        var fixture = try makeFixture()
        try fixture.ledger.setCleared(true, forAccount: fixture.bank.id, in: fixture.groceriesTx)

        let data = try JSONEncoder().encode(fixture.ledger)
        let decoded = try JSONDecoder().decode(Ledger.self, from: data)

        let tx = try XCTUnwrap(decoded.transactions.first { $0.id == fixture.groceriesTx })
        let bankPosting = try XCTUnwrap(tx.postings.first { $0.accountID == fixture.bank.id })

        XCTAssertTrue(bankPosting.cleared)
    }
}
