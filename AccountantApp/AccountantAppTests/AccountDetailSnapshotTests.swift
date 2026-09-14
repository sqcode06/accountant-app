import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

struct AccountDetailSnapshotTests {
    private let eur = Currency("EUR")
    private let usd = Currency("USD")

    @Test func buildsNewestFirstCurrencyScopedEntriesWithIndependentRunningBalances() throws {
        let bank = Account(name: "Everyday", kind: .asset)
        let salary = Account(name: "Salary", kind: .income)
        let groceries = Account(name: "Groceries", kind: .expense)
        let savings = Account(name: "Savings", kind: .asset)
        var ledger = ledger(with: [bank, salary, groceries, savings])

        let deposit = transaction(
            at: 100,
            memo: "Payday",
            postings: [
                Posting(accountID: bank.id, money: money(100), cleared: true),
                Posting(accountID: salary.id, money: money(-100))
            ]
        )
        let otherCurrency = transaction(
            at: 150,
            memo: "USD only",
            postings: [
                Posting(accountID: bank.id, money: Money(50, currency: usd)),
                Posting(accountID: salary.id, money: Money(-50, currency: usd))
            ]
        )
        let draft = transaction(
            at: 200,
            memo: "Market",
            state: .draft,
            postings: [
                Posting(accountID: bank.id, money: money(-30)),
                Posting(accountID: groceries.id, money: money(30))
            ]
        )
        let transfer = transaction(
            at: 300,
            memo: "  \n",
            postings: [
                Posting(accountID: bank.id, money: money(-20), cleared: true),
                Posting(accountID: savings.id, money: money(20))
            ]
        )

        // Add out of order so the expected statement order does not mirror storage.
        try ledger.addTransaction(transfer)
        try ledger.addTransaction(otherCurrency)
        try ledger.addTransaction(deposit)
        try ledger.addTransaction(draft)

        let snapshot = AccountDetailSnapshot.make(from: ledger, account: bank, currency: eur)

        #expect(snapshot.entries.map(\.id) == [transfer.id, draft.id, deposit.id])
        #expect(snapshot.entries.map(\.delta.amount) == [-20, -30, 100])
        // Running balances remain chronological even though display rows are reversed.
        #expect(snapshot.entries.map(\.runningBalance.amount) == [50, 70, 100])
        #expect(snapshot.entries.allSatisfy { $0.delta.currency == eur })
        #expect(snapshot.entries.map(\.isDraft) == [false, true, false])
        #expect(snapshot.entries.first?.counterparties == ["Savings"])
        #expect(snapshot.entries.first?.title == "Savings")
        #expect(snapshot.balance == money(50))
        #expect(snapshot.clearedBalance == money(80))
        #expect(snapshot.pendingBalance == money(-30))
        #expect(snapshot.pendingCount == 1)
        #expect(snapshot.hasPending)
    }

    @Test func partlyClearedOwnPostingsContributeOnlyTheirClearedAmounts() throws {
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let merchant = Account(name: "Merchant", kind: .expense)
        var ledger = ledger(with: [bank, merchant])
        let split = transaction(
            at: 100,
            memo: "Split settlement",
            postings: [
                Posting(accountID: bank.id, money: money(-70), cleared: true),
                Posting(accountID: bank.id, money: money(-30), cleared: false),
                Posting(accountID: merchant.id, money: money(100))
            ]
        )
        try ledger.addTransaction(split)

        let snapshot = AccountDetailSnapshot.make(from: ledger, account: bank, currency: eur)

        #expect(snapshot.balance == money(-100))
        #expect(snapshot.clearedBalance == money(-70))
        #expect(snapshot.pendingBalance == money(-30))
        #expect(snapshot.entries.first?.delta == money(-100))
        #expect(snapshot.entries.first?.isCleared == false)
        #expect(snapshot.pendingCount == 1)
    }

    @Test func zeroNetUnclearedLineIsVisibleWithoutCreatingAPendingBalance() throws {
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let offset = Account(name: "Internal offset", kind: .clearing)
        var ledger = ledger(with: [bank, offset])
        let zeroNet = transaction(
            at: 100,
            memo: nil,
            postings: [
                Posting(accountID: bank.id, money: money(25)),
                Posting(accountID: bank.id, money: money(-25)),
                Posting(accountID: offset.id, money: money(0))
            ]
        )
        try ledger.addTransaction(zeroNet)

        let snapshot = AccountDetailSnapshot.make(from: ledger, account: bank, currency: eur)

        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.delta == money(0))
        #expect(snapshot.entries.first?.runningBalance == money(0))
        #expect(snapshot.entries.first?.isCleared == false)
        #expect(snapshot.entries.first?.title == "Internal offset")
        #expect(snapshot.pendingBalance == money(0))
        #expect(snapshot.pendingCount == 1)
        #expect(!snapshot.hasPending)
    }

    private func money(_ amount: Decimal) -> Money {
        Money(amount, currency: eur)
    }

    private func transaction(
        at timestamp: TimeInterval,
        memo: String?,
        state: TransactionState = .finalized,
        postings: [Posting]
    ) -> Transaction {
        let date = Date(timeIntervalSince1970: timestamp)
        return Transaction(
            date: date,
            memo: memo,
            postings: postings,
            state: state,
            createdAt: date,
            updatedAt: date,
            finalizedAt: state == .finalized ? date : nil
        )
    }

    private func ledger(with accounts: [Account]) -> Ledger {
        var ledger = Ledger()
        for account in accounts { ledger.addAccount(account) }
        return ledger
    }
}
