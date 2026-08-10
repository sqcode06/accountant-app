import XCTest
@testable import AccountantCore

/// Backs the capture-then-review loop: record quickly during the day, confirm the
/// batch in the evening.
final class BatchReviewTests: XCTestCase {

    private let eur = Currency("EUR")

    private struct Fixture {
        var ledger: Ledger
        let bank: Account
        let groceries: Account
        let ids: [TransactionID]
    }

    private func makeFixture(count: Int = 3) throws -> Fixture {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        var ids: [TransactionID] = []

        for index in 0..<count {
            let tx = try Transaction.draftExpense(
                paidFrom: bank.id,
                category: groceries.id,
                amount: Money(Decimal(10 + index), currency: eur),
                date: Date(timeIntervalSince1970: TimeInterval(100 * (index + 1)))
            )
            try ledger.addTransaction(tx)
            ids.append(tx.id)
        }

        return Fixture(ledger: ledger, bank: bank, groceries: groceries, ids: ids)
    }

    // MARK: - Listing

    func testDraftsAreListedOldestFirst() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(fixture.ledger.draftTransactions().map(\.id), fixture.ids)
    }

    func testFinalizedTransactionsLeaveTheReviewQueue() throws {
        var fixture = try makeFixture()

        try fixture.ledger.finalizeTransaction(id: fixture.ids[0])

        XCTAssertEqual(
            fixture.ledger.draftTransactions().map(\.id),
            Array(fixture.ids.dropFirst())
        )
    }

    // MARK: - Batch confirmation

    func testConfirmingABatchFinalizesEveryTransaction() throws {
        var fixture = try makeFixture()

        let count = try fixture.ledger.finalizeTransactions(ids: fixture.ids)

        XCTAssertEqual(count, 3)
        XCTAssertTrue(fixture.ledger.draftTransactions().isEmpty)
        XCTAssertTrue(fixture.ledger.transactions.allSatisfy { $0.state == .finalized })
    }

    func testAlreadyFinalizedEntriesAreSkippedNotRejected() throws {
        var fixture = try makeFixture()

        try fixture.ledger.finalizeTransaction(id: fixture.ids[0])
        let count = try fixture.ledger.finalizeTransactions(ids: fixture.ids)

        XCTAssertEqual(count, 2, "The already-confirmed one should be skipped, not counted")
        XCTAssertTrue(fixture.ledger.draftTransactions().isEmpty)
    }

    func testConfirmingAnEmptyBatchIsANoOp() throws {
        var fixture = try makeFixture()
        let before = fixture.ledger

        let count = try fixture.ledger.finalizeTransactions(ids: [])

        XCTAssertEqual(count, 0)
        XCTAssertEqual(fixture.ledger, before)
    }

    // MARK: - Atomicity

    func testAnUnknownIDFailsTheWholeBatchAndCommitsNothing() throws {
        var fixture = try makeFixture()
        let before = fixture.ledger

        XCTAssertThrowsError(
            try fixture.ledger.finalizeTransactions(ids: fixture.ids + [TransactionID()])
        )

        // A partially confirmed batch is worse than a failed one: there would be no
        // way to tell which half went through.
        XCTAssertEqual(fixture.ledger, before)
        XCTAssertEqual(fixture.ledger.draftTransactions().count, 3)
    }

    func testAnInvalidEntryMidBatchRollsBackTheEarlierOnes() throws {
        var fixture = try makeFixture()

        // A draft pointing at an archived account cannot be confirmed.
        //
        // `archiveAccount` refuses while open drafts reference the account, so this
        // state is unreachable through the normal API — but a merge can produce it
        // by bringing in an archived account while a local draft still points at
        // it. Forced here with the module-internal hook to reproduce that.
        var stale = Account(name: "Closed card", kind: .liability, currency: eur)
        fixture.ledger.addAccount(stale)

        let doomed = try Transaction.draftExpense(
            paidFrom: stale.id,
            category: fixture.groceries.id,
            amount: Money(Decimal(5), currency: eur),
            date: Date(timeIntervalSince1970: 400)
        )
        try fixture.ledger.addTransaction(doomed)

        stale.status = .archived
        fixture.ledger._setAccount(stale)

        let before = fixture.ledger

        XCTAssertThrowsError(
            try fixture.ledger.finalizeTransactions(ids: fixture.ids + [doomed.id])
        )

        XCTAssertEqual(fixture.ledger, before)
        XCTAssertEqual(fixture.ledger.draftTransactions().count, 4)
    }

    // MARK: - Ordering independence

    func testConfirmationOrderDoesNotAffectTheResult() throws {
        var forwards = try makeFixture()
        var backwards = forwards

        try forwards.ledger.finalizeTransactions(
            ids: forwards.ids,
            now: Date(timeIntervalSince1970: 9_000)
        )
        try backwards.ledger.finalizeTransactions(
            ids: backwards.ids.reversed(),
            now: Date(timeIntervalSince1970: 9_000)
        )

        XCTAssertEqual(forwards.ledger, backwards.ledger)
    }
}
