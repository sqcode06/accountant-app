import XCTest
@testable import AccountantCore

final class TransactionLifecycleTests: XCTestCase {

    func testDraftCanBeUpdatedButFinalizedCannot() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let cash = Account(name: "Cash")
        let bank = Account(name: "Bank")
        ledger.addAccount(cash)
        ledger.addAccount(bank)

        let tx = Transaction.draft(
            memo: "Initial",
            postings: [
                Posting(accountID: cash.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: bank.id, money: Money(Decimal(10), currency: eur))
            ]
        )

        try ledger.addTransaction(tx)

        // Update memo while draft
        try ledger.updateDraftTransaction(id: tx.id) { t in
            t.memo = "Edited memo"
        }

        // Finalize
        try ledger.finalizeTransaction(id: tx.id)

        // Now updating should throw
        XCTAssertThrowsError(
            try ledger.updateDraftTransaction(id: tx.id) { t in
                t.memo = "Should fail"
            }
        )
    }

    func testFinalizedSnapshotFiltersDrafts() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let a = Account(name: "A")
        let b = Account(name: "B")
        ledger.addAccount(a); ledger.addAccount(b)

        let draft = Transaction.draft(postings: [
            Posting(accountID: a.id, money: Money(Decimal(-1), currency: eur)),
            Posting(accountID: b.id, money: Money(Decimal(1), currency: eur))
        ])

        let fin = Transaction.finalized(postings: [
            Posting(accountID: a.id, money: Money(Decimal(-2), currency: eur)),
            Posting(accountID: b.id, money: Money(Decimal(2), currency: eur))
        ])

        try ledger.addTransaction(draft)
        try ledger.addTransaction(fin)

        let snap = ledger.exportFinalizedSnapshot()
        XCTAssertEqual(snap.transactions.count, 1)
        XCTAssertEqual(snap.transactions.first?.state, .finalized)
    }
}
