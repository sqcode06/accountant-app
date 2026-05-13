import XCTest
@testable import AccountantCore

final class MergeSafetyTests: XCTestCase {

    func testIncomingDraftTransactionsAreIgnored() throws {
        let eur = Currency("EUR")

        var local = Ledger()
        var incoming = Ledger()

        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Expense", kind: .expense)

        local.addAccount(bank)
        local.addAccount(expense)

        incoming.addAccount(bank)
        incoming.addAccount(expense)

        let draft = Transaction.draft(
            memo: "Incoming draft should be ignored",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: expense.id, money: Money(Decimal(10), currency: eur))
            ]
        )

        try incoming.addTransaction(draft)

        let report = try local.mergeFinalized(from: incoming)

        XCTAssertEqual(report.addedTransactions, 0)
        XCTAssertEqual(report.skippedTransactions, 0)
        XCTAssertEqual(local.transactions.count, 0)
    }

    func testInvalidIncomingFinalizedTransactionThrowsDedicatedMergeError() throws {
        let eur = Currency("EUR")

        var local = Ledger()
        var incoming = Ledger()

        let bank = Account(name: "Bank", kind: .asset)
        let expense = Account(name: "Expense", kind: .expense)

        local.addAccount(bank)
        local.addAccount(expense)

        incoming.addAccount(bank)
        incoming.addAccount(expense)

        let invalid = Transaction(
            date: Date(timeIntervalSince1970: 100),
            memo: "Broken incoming transaction",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: expense.id, money: Money(Decimal(9), currency: eur))
            ],
            state: .finalized
        )

        // Bypass normal addTransaction because it correctly rejects invalid transactions.
        incoming._appendTransaction(invalid)

        XCTAssertThrowsError(try local.mergeFinalized(from: incoming)) { error in
            XCTAssertEqual(
                error as? LedgerMergeError,
                LedgerMergeError.incomingTransactionInvalid(invalid.id)
            )
        }

        XCTAssertEqual(local.transactions.count, 0)
    }

    func testMergeFailureDoesNotPartiallyMutateLedger() throws {
        let eur = Currency("EUR")

        var local = Ledger()
        var incoming = Ledger()

        let localBank = Account(name: "Local Bank", kind: .asset)
        let localExpense = Account(name: "Local Expense", kind: .expense)

        local.addAccount(localBank)
        local.addAccount(localExpense)

        let originalTransaction = Transaction.finalized(
            memo: "Original local transaction",
            postings: [
                Posting(accountID: localBank.id, money: Money(Decimal(-5), currency: eur)),
                Posting(accountID: localExpense.id, money: Money(Decimal(5), currency: eur))
            ]
        )

        try local.addTransaction(originalTransaction)

        let before = local

        let incomingBank = Account(name: "Incoming Bank", kind: .asset)
        let incomingExpense = Account(name: "Incoming Expense", kind: .expense)

        incoming.addAccount(incomingBank)
        incoming.addAccount(incomingExpense)

        let invalid = Transaction(
            date: Date(timeIntervalSince1970: 200),
            memo: "Invalid incoming transaction",
            postings: [
                Posting(accountID: incomingBank.id, money: Money(Decimal(-20), currency: eur)),
                Posting(accountID: incomingExpense.id, money: Money(Decimal(19), currency: eur))
            ],
            state: .finalized
        )

        incoming._appendTransaction(invalid)

        XCTAssertThrowsError(try local.mergeFinalized(from: incoming))

        XCTAssertEqual(local, before)
    }

    func testIncomingTransactionReferencingUnknownAccountThrowsDedicatedMergeError() throws {
        let eur = Currency("EUR")

        var local = Ledger()
        var incoming = Ledger()

        let bank = Account(name: "Bank", kind: .asset)
        let knownExpense = Account(name: "Known Expense", kind: .expense)
        let ghostAccountID = AccountID()

        local.addAccount(bank)
        local.addAccount(knownExpense)

        incoming.addAccount(bank)
        // Intentionally do NOT add account for ghostAccountID.

        let tx = Transaction(
            date: Date(timeIntervalSince1970: 300),
            memo: "References missing account",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-12), currency: eur)),
                Posting(accountID: ghostAccountID, money: Money(Decimal(12), currency: eur))
            ],
            state: .finalized
        )

        incoming._appendTransaction(tx)

        XCTAssertThrowsError(try local.mergeFinalized(from: incoming)) { error in
            XCTAssertEqual(
                error as? LedgerMergeError,
                LedgerMergeError.incomingReferencesUnknownAccount(
                    accountID: ghostAccountID,
                    transactionID: tx.id
                )
            )
        }

        XCTAssertEqual(local.transactions.count, 0)
    }
}