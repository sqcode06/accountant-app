import XCTest
@testable import AccountantCore

final class MergeTests: XCTestCase {

    private let eur = Currency("EUR")

    private func makeBaseLedgers() -> (Ledger, Ledger, Account, Account) {
        var a = Ledger()
        var b = Ledger()

        let bank = Account(name: "Bank")
        let ext  = Account(name: "External")

        a.addAccount(bank); a.addAccount(ext)
        b.addAccount(bank); b.addAccount(ext)

        return (a, b, bank, ext)
    }

    private func tx(
        id: String,
        date: TimeInterval,
        memo: String? = nil,
        bank: Account,
        ext: Account,
        amount: Decimal,
        state: TransactionState,
        createdAt: TimeInterval,
        origin: TransactionOrigin?
    ) -> Transaction {
        Transaction(
            id: TransactionID(UUID(uuidString: id)!),
            date: Date(timeIntervalSince1970: date),
            memo: memo,
            postings: [
                Posting(accountID: bank.id, money: Money(-amount, currency: eur)),
                Posting(accountID: ext.id,  money: Money(amount, currency: eur)),
            ],
            state: state,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt),
            finalizedAt: state == .finalized ? Date(timeIntervalSince1970: createdAt) : nil,
            origin: origin
        )
    }

    func testMergeDeduplicatesByOriginEvenIfIDsDiffer() throws {
        let o = TransactionOrigin(source: "MyBank", externalID: "ABC123")
        var (a, b, bank, ext) = makeBaseLedgers()

        try a.addTransaction(tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Coffee",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 1001,
            origin: o
        ))

        try b.addTransaction(tx(
            id: "22222222-2222-2222-2222-222222222222",
            date: 1000, memo: "Coffee (same logical tx)",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 2000,
            origin: o
        ))

        let report = try a.mergeFinalized(from: b)
        XCTAssertEqual(report.addedTransactions, 0)
        XCTAssertEqual(report.skippedTransactions, 1)
        XCTAssertEqual(a.transactions.filter { $0.state == .finalized }.count, 1)
    }

    func testMergeDoesNotDeduplicateByOriginWhenOptionOff() throws {
        let o = TransactionOrigin(source: "MyBank", externalID: "ABC123")
        var (a, b, bank, ext) = makeBaseLedgers()

        try a.addTransaction(tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Coffee",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 1001,
            origin: o
        ))

        try b.addTransaction(tx(
            id: "22222222-2222-2222-2222-222222222222",
            date: 1000, memo: "Coffee (same logical tx)",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 2000,
            origin: o
        ))

        var opts = LedgerMergeOptions()
        opts.deduplicateByOrigin = false

        let report = try a.mergeFinalized(from: b, options: opts)
        XCTAssertEqual(report.addedTransactions, 1)
        XCTAssertEqual(a.transactions.filter { $0.state == .finalized }.count, 2)
    }

    func testMergeOriginConflictDefaultIsError() throws {
        let o = TransactionOrigin(source: "MyBank", externalID: "ABC123")
        var (a, b, bank, ext) = makeBaseLedgers()

        let local = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Coffee",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 1001,
            origin: o
        )

        // Same origin, different financial signature (date differs)
        let incoming = tx(
            id: "22222222-2222-2222-2222-222222222222",
            date: 1005, memo: "Coffee (conflict)",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 2000,
            origin: o
        )

        try a.addTransaction(local)
        try b.addTransaction(incoming)

        XCTAssertThrowsError(try a.mergeFinalized(from: b)) { err in
            guard case LedgerMergeError.transactionOriginConflict(let origin, _, _) = err else {
                return XCTFail("Expected transactionOriginConflict, got: \(err)")
            }
            XCTAssertEqual(origin, o)
        }

        XCTAssertEqual(a.transactions.filter { $0.state == .finalized }.count, 1)
        XCTAssertEqual(a.transactions.first?.id, local.id)
    }

    func testMergeOriginConflictKeepLocal() throws {
        let o = TransactionOrigin(source: "MyBank", externalID: "ABC123")
        var (a, b, bank, ext) = makeBaseLedgers()

        let local = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Coffee",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 1001,
            origin: o
        )

        let incoming = tx(
            id: "22222222-2222-2222-2222-222222222222",
            date: 1005, memo: "Coffee (conflict)",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 2000,
            origin: o
        )

        try a.addTransaction(local)
        try b.addTransaction(incoming)

        var opts = LedgerMergeOptions()
        opts.transactionConflictResolution = .keepLocal

        let report = try a.mergeFinalized(from: b, options: opts)
        XCTAssertEqual(report.addedTransactions, 0)
        XCTAssertEqual(report.skippedTransactions, 1)
        XCTAssertTrue(report.conflicts.contains(.transactionOriginMismatch(origin: o)))
        XCTAssertEqual(report.conflicts.count, 1)
        XCTAssertEqual(a.transactions.filter { $0.state == .finalized }.count, 1)
        XCTAssertEqual(a.transactions.first?.id, local.id)
    }

    /// Spec: dedupe-by-origin + preferIncoming should NOT change the local tx ID.
    func testMergeOriginConflictPreferIncomingKeepsLocalIDAndUpdatesContent() throws {
        let o = TransactionOrigin(source: "MyBank", externalID: "ABC123")
        var (a, b, bank, ext) = makeBaseLedgers()

        let local = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Coffee",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 1001,
            origin: o
        )

        let incoming = tx(
            id: "22222222-2222-2222-2222-222222222222",
            date: 1005, memo: "Coffee (incoming wins)",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 2000,
            origin: o
        )

        try a.addTransaction(local)
        try b.addTransaction(incoming)

        var opts = LedgerMergeOptions()
        opts.transactionConflictResolution = .preferIncoming

        let report = try a.mergeFinalized(from: b, options: opts)
        XCTAssertEqual(report.addedTransactions, 0)
        XCTAssertEqual(a.transactions.filter { $0.state == .finalized }.count, 1)

        let merged = try XCTUnwrap(a.transactions.first { $0.state == .finalized })
        XCTAssertEqual(merged.id, local.id)                 // stable identity
        XCTAssertEqual(merged.date, incoming.date)          // incoming wins
        XCTAssertEqual(merged.postings, incoming.postings)  // incoming wins
        XCTAssertEqual(merged.origin, o)
    }

    /// Regression: replace-by-ID must update the in-memory origin index,
    /// otherwise later txs with the new origin will be incorrectly appended.
    func testMergePreferIncomingByIDUpdatesOriginIndex() throws {
        let oOld = TransactionOrigin(source: "MyBank", externalID: "OLD")
        let oNew = TransactionOrigin(source: "MyBank", externalID: "NEW")

        var (a, b, bank, ext) = makeBaseLedgers()

        let local = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Local",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 1001,
            origin: oOld
        )

        // Same ID, different signature and origin changes.
        let incomingReplacement = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Incoming replacement",
            bank: bank, ext: ext,
            amount: 4, state: .finalized,
            createdAt: 2000,
            origin: oNew
        )

        // Different ID, same origin + same signature as the replacement => should be deduped.
        let incomingDupByOrigin = tx(
            id: "22222222-2222-2222-2222-222222222222",
            date: 1000, memo: "Dup by origin",
            bank: bank, ext: ext,
            amount: 4, state: .finalized,
            createdAt: 2001,
            origin: oNew
        )

        try a.addTransaction(local)
        try b.addTransaction(incomingReplacement)
        try b.addTransaction(incomingDupByOrigin)

        var opts = LedgerMergeOptions()
        opts.transactionConflictResolution = .preferIncoming

        let report = try a.mergeFinalized(from: b, options: opts)

        XCTAssertEqual(report.addedTransactions, 0)
        XCTAssertEqual(a.transactions.filter { $0.state == .finalized }.count, 1)

        let merged = try XCTUnwrap(a.transactions.first { $0.state == .finalized })
        XCTAssertEqual(merged.origin, oNew)
        XCTAssertEqual(merged.postings, incomingReplacement.postings)
    }

    /// Spec: mergeFinalized must not create duplicate tx IDs (even if local is a draft).
    func testMergeFinalizedSameIDAsLocalDraftIsIDConflictByDefault() throws {
        let o = TransactionOrigin(source: "MyBank", externalID: "ABC123")
        var (a, b, bank, ext) = makeBaseLedgers()

        let draftLocal = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Draft local",
            bank: bank, ext: ext,
            amount: 3, state: .draft,
            createdAt: 1001,
            origin: nil
        )

        let incomingFinal = tx(
            id: "11111111-1111-1111-1111-111111111111",
            date: 1000, memo: "Incoming finalized",
            bank: bank, ext: ext,
            amount: 3, state: .finalized,
            createdAt: 2000,
            origin: o
        )

        try a.addTransaction(draftLocal)
        try b.addTransaction(incomingFinal)

        XCTAssertThrowsError(try a.mergeFinalized(from: b)) { err in
            guard case LedgerMergeError.transactionIDConflict(let id, _, _) = err else {
                return XCTFail("Expected transactionIDConflict, got: \(err)")
            }
            XCTAssertEqual(id, draftLocal.id)
        }
    }
}
