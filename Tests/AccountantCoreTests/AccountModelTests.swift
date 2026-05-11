import XCTest
@testable import AccountantCore

final class AccountModelTests: XCTestCase {
    private let eur = Currency("EUR")

    func testAccountKindAndStatusRoundTripThroughPersistence() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, status: .active)
        let oldGroceries = Account(name: "Old Groceries", kind: .expense, status: .archived)

        ledger.addAccount(bank)
        ledger.addAccount(oldGroceries)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("ledger.json")
        let store = JSONLedgerStore(fileURL: fileURL)

        try store.save(ledger)
        let loaded = try store.load()

        XCTAssertEqual(loaded.accounts[bank.id]?.kind, .asset)
        XCTAssertEqual(loaded.accounts[bank.id]?.status, .active)

        XCTAssertEqual(loaded.accounts[oldGroceries.id]?.kind, .expense)
        XCTAssertEqual(loaded.accounts[oldGroceries.id]?.status, .archived)
    }

    func testArchivedAccountCannotReceiveNewTransactionsAndDoesNotMutateLedger() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)
        try ledger.archiveAccount(id: groceries.id)

        let tx = Transaction(
            memo: "Should not be accepted",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-20), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(20), currency: eur))
            ]
        )

        XCTAssertThrowsError(try ledger.addTransaction(tx)) { error in
            XCTAssertEqual(error as? LedgerError, LedgerError.accountArchived(groceries.id))
        }

        XCTAssertEqual(ledger.transactions.count, 0)
    }

    func testFinalizedHistoricalTransactionRemainsValidAfterAccountIsArchived() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let tx = Transaction.finalized(
            memo: "Groceries",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-15), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(15), currency: eur))
            ]
        )

        try ledger.addTransaction(tx)
        try ledger.archiveAccount(id: groceries.id)

        XCTAssertEqual(ledger.accounts[groceries.id]?.status, .archived)
        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.balance(of: groceries.id, currency: eur).amount, Decimal(15))
    }

    func testCannotArchiveAccountWithOpenDraftsAndDoesNotMutateLedger() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let draft = Transaction.draft(
            memo: "Unfinalized groceries",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-12), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(12), currency: eur))
            ]
        )

        try ledger.addTransaction(draft)

        XCTAssertThrowsError(try ledger.archiveAccount(id: groceries.id)) { error in
            XCTAssertEqual(error as? LedgerError, LedgerError.accountHasOpenDrafts(groceries.id))
        }

        XCTAssertEqual(ledger.accounts[groceries.id]?.status, .active)
        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.transactions.first?.state, .draft)
    }

    func testUpdatingDraftToUseArchivedAccountThrowsAndDoesNotMutateLedger() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)
        let transport = Account(name: "Transport", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)
        ledger.addAccount(transport)
        try ledger.archiveAccount(id: transport.id)

        let draft = Transaction.draft(
            memo: "Groceries",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-30), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(30), currency: eur))
            ]
        )
        try ledger.addTransaction(draft)

        XCTAssertThrowsError(
            try ledger.updateDraftTransaction(id: draft.id) { tx in
                tx.memo = "Transport instead"
                tx.postings = [
                    Posting(accountID: bank.id, money: Money(Decimal(-30), currency: eur)),
                    Posting(accountID: transport.id, money: Money(Decimal(30), currency: eur))
                ]
            }
        ) { error in
            XCTAssertEqual(error as? LedgerError, LedgerError.accountArchived(transport.id))
        }

        let unchanged = try XCTUnwrap(ledger.transactions.first { $0.id == draft.id })
        XCTAssertEqual(unchanged.memo, "Groceries")
        XCTAssertEqual(unchanged.postings[1].accountID, groceries.id)
    }

    func testRestoreAccountAllowsNewTransactionsAgain() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        try ledger.archiveAccount(id: groceries.id)
        try ledger.restoreAccount(id: groceries.id)

        let tx = Transaction.draft(
            memo: "Groceries after restore",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(10), currency: eur))
            ]
        )

        try ledger.addTransaction(tx)

        XCTAssertEqual(ledger.accounts[groceries.id]?.status, .active)
        XCTAssertEqual(ledger.transactions.count, 1)
    }

    func testArchivingUnknownAccountThrowsDedicatedError() {
        var ledger = Ledger()
        let missingID = AccountID(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)

        XCTAssertThrowsError(try ledger.archiveAccount(id: missingID)) { error in
            XCTAssertEqual(error as? LedgerError, LedgerError.accountNotFound(missingID))
        }
    }
}
