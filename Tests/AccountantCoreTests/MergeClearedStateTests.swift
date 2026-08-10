import XCTest
@testable import AccountantCore

/// Cleared state is local bookkeeping, not part of the financial fact.
///
/// Merge compares transactions by financial signature. If that signature included
/// `Posting.cleared`, then a transaction you had reconciled on one device would
/// no longer match the same transaction arriving from another, and merge would
/// treat an agreement as a conflict.
final class MergeClearedStateTests: XCTestCase {

    private let eur = Currency("EUR")

    private struct Pair {
        let local: Ledger
        let incoming: Ledger
        let transactionID: TransactionID
        let bankID: AccountID
    }

    /// The same finalized transaction on two devices, cleared locally only.
    private func makePair() throws -> Pair {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
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

        // Both devices hold the identical finalized fact.
        let incoming = ledger

        // Only this device has reconciled it.
        var local = ledger
        try local.setCleared(true, forAccount: bank.id, in: tx.id)

        return Pair(local: local, incoming: incoming, transactionID: tx.id, bankID: bank.id)
    }

    // MARK: - Signature

    func testClearingDoesNotChangeTheFinancialSignature() throws {
        let pair = try makePair()

        let localTx = try XCTUnwrap(pair.local.transactions.first)
        let incomingTx = try XCTUnwrap(pair.incoming.transactions.first)

        XCTAssertNotEqual(localTx.postings, incomingTx.postings, "Precondition: cleared flags differ")
        XCTAssertEqual(
            localTx.financialSignature,
            incomingTx.financialSignature,
            "Clearing must not alter the financial signature"
        )
    }

    func testDifferentAmountStillChangesTheSignature() throws {
        // The signature must stay sensitive to what it is actually for.
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let cheap = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(30), currency: eur),
            date: Date(timeIntervalSince1970: 100)
        )
        let dear = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(31), currency: eur),
            date: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNotEqual(cheap.financialSignature, dear.financialSignature)
    }

    // MARK: - Merge behaviour

    func testMergingAnAlreadyClearedTransactionIsNotAConflict() throws {
        let pair = try makePair()
        var local = pair.local

        let report = try local.mergeFinalized(from: pair.incoming)

        XCTAssertTrue(
            report.conflicts.isEmpty,
            "Reconciling on one device must not create a sync conflict"
        )
        XCTAssertEqual(report.skippedTransactions, 1)
        XCTAssertEqual(report.addedTransactions, 0)
    }

    func testMergePreservesLocalClearedState() throws {
        let pair = try makePair()
        var local = pair.local

        try local.mergeFinalized(from: pair.incoming)

        let merged = try XCTUnwrap(local.transactions.first { $0.id == pair.transactionID })
        let bankPosting = try XCTUnwrap(merged.postings.first { $0.accountID == pair.bankID })

        XCTAssertTrue(
            bankPosting.cleared,
            "A completed reconciliation must survive a merge that changes nothing financial"
        )
    }

    func testMergedLedgerStillReconcilesAsCleared() throws {
        let pair = try makePair()
        var local = pair.local

        try local.mergeFinalized(from: pair.incoming)

        let report = try local.reconcileAccount(
            pair.bankID,
            statementBalance: Money(Decimal(-30), currency: eur),
            asOf: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.clearedBalance.amount, Decimal(-30))
        XCTAssertTrue(report.uncleared.isEmpty)
    }
}
