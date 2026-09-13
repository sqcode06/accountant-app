import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

struct ImportReviewTests {
    @Test func reviewShowsPurchaseIncomeAndRefundDirectionsWithoutAbsorbingFees() throws {
        let fixture = ImportReviewFixture()
        let purchase = fixture.purchaseWithFee()
        let purchaseDetails = DraftReviewDetails(transaction: purchase, accounts: fixture.ledger.accounts)
        #expect(purchaseDetails.amount == Money(Decimal(string: "-24.60")!, currency: Currency("EUR")))
        #expect(purchaseDetails.feePostings == [purchase.postings[2]])
        #expect(purchaseDetails.sourceName == "Bank")

        let income = try Transaction.draftIncome(
            receivedIn: fixture.bank.id, source: fixture.salary.id,
            amount: Money(100, currency: Currency("EUR")), date: fixture.date
        )
        let incomeDetails = DraftReviewDetails(transaction: income, accounts: fixture.ledger.accounts)
        #expect(incomeDetails.amount == Money(100, currency: Currency("EUR")))
        #expect(incomeDetails.categoryName == "Salary")

        let refund = Transaction.draft(date: fixture.date, postings: [
            Posting(accountID: fixture.bank.id, money: Money(5, currency: Currency("EUR")), role: .statement),
            Posting(accountID: fixture.groceries.id, money: Money(-5, currency: Currency("EUR")), role: .counterparty)
        ])
        let refundDetails = DraftReviewDetails(transaction: refund, accounts: fixture.ledger.accounts)
        #expect(refundDetails.amount == Money(5, currency: Currency("EUR")))
        #expect(refundDetails.categoryName == "Groceries")
    }

    @MainActor @Test func incompatibleCategoryCurrencyLeavesDraftAndFeeUnchanged() async throws {
        let fixture = ImportReviewFixture()
        let transaction = fixture.purchaseWithFee()
        let dollarCategory = Account(name: "Dollar spending", kind: .expense, currency: Currency("USD"))
        var ledger = fixture.ledger
        ledger.addAccount(dollarCategory)
        try ledger.addTransaction(transaction)
        let state = AppState(repository: ImportReviewRepository(ledger: ledger))
        await state.loadIfNeeded()

        #expect(!(await state.recategorizeDraft(id: transaction.id, to: dollarCategory.id)))
        #expect(state.ledger.transactions.first == transaction)
        #expect(state.lastError != nil)
    }

    @MainActor @Test func recategorizingPurchasePreservesSeparateFee() async throws {
        let fixture = ImportReviewFixture()
        let transaction = fixture.purchaseWithFee()
        var ledger = fixture.ledger
        try ledger.addTransaction(transaction)
        let state = AppState(repository: ImportReviewRepository(ledger: ledger))
        await state.loadIfNeeded()

        #expect(await state.recategorizeDraft(id: transaction.id, to: fixture.groceries.id))
        let updated = try #require(state.ledger.transactions.first)
        #expect(updated.postings[1].accountID == fixture.groceries.id)
        #expect(updated.postings[2] == transaction.postings[2])
        #expect(updated.postings[0] == transaction.postings[0])
        #expect(updated.postings[1].role == .counterparty)
    }

    @MainActor @Test func recategorizingIncomeChangesItsIncomePosting() async throws {
        let fixture = ImportReviewFixture()
        let transaction = try Transaction.draftIncome(
            receivedIn: fixture.bank.id, source: fixture.salary.id,
            amount: Money(100, currency: Currency("EUR")), date: fixture.date, memo: "Payroll"
        )
        var ledger = fixture.ledger
        try ledger.addTransaction(transaction)
        let state = AppState(repository: ImportReviewRepository(ledger: ledger))
        await state.loadIfNeeded()

        #expect(await state.recategorizeDraft(id: transaction.id, to: fixture.otherIncome.id))
        let updated = try #require(state.ledger.transactions.first)
        #expect(updated.postings[1].accountID == fixture.otherIncome.id)
        #expect(updated.postings[0] == transaction.postings[0])
    }

    @MainActor @Test func ambiguousLegacySplitRemainsUnchanged() async throws {
        let fixture = ImportReviewFixture()
        var transaction = fixture.purchaseWithFee()
        transaction.postings = transaction.postings.map {
            Posting(accountID: $0.accountID, money: $0.money, cleared: $0.cleared)
        }
        var ledger = fixture.ledger
        try ledger.addTransaction(transaction)
        let state = AppState(repository: ImportReviewRepository(ledger: ledger))
        await state.loadIfNeeded()

        #expect(!(await state.recategorizeDraft(id: transaction.id, to: fixture.groceries.id)))
        #expect(state.ledger.transactions.first == transaction)
        #expect(state.lastError != nil)
    }

    @MainActor @Test func partialRoleMetadataCannotFallBackToAnUntaggedCategory() async throws {
        let fixture = ImportReviewFixture()
        var transaction = fixture.purchaseWithFee()
        transaction.postings[1].role = nil
        var ledger = fixture.ledger
        try ledger.addTransaction(transaction)
        let state = AppState(repository: ImportReviewRepository(ledger: ledger))
        await state.loadIfNeeded()

        #expect(!(await state.recategorizeDraft(id: transaction.id, to: fixture.groceries.id)))
        #expect(state.ledger.transactions.first == transaction)
        #expect(state.lastError != nil)
    }
}

private struct ImportReviewFixture {
    let date = Date(timeIntervalSince1970: 1_789_300_800)
    let bank = Account(name: "Bank", kind: .asset, currency: Currency("EUR"))
    let uncategorised = Account(name: "Uncategorised", kind: .expense)
    let groceries = Account(name: "Groceries", kind: .expense)
    let fees = Account(name: "Bank fees", kind: .expense)
    let salary = Account(name: "Salary", kind: .income)
    let otherIncome = Account(name: "Other income", kind: .income)

    var ledger: Ledger {
        var ledger = Ledger()
        for account in [bank, uncategorised, groceries, fees, salary, otherIncome] {
            ledger.addAccount(account)
        }
        return ledger
    }

    func purchaseWithFee() -> Transaction {
        .draft(date: date, memo: "Shop", postings: [
            Posting(accountID: bank.id, money: Money(-25, currency: Currency("EUR")), role: .statement),
            Posting(accountID: uncategorised.id, money: Money(Decimal(string: "24.60")!, currency: Currency("EUR")), role: .counterparty),
            Posting(accountID: fees.id, money: Money(Decimal(string: "0.40")!, currency: Currency("EUR")), cleared: true, role: .fee)
        ])
    }
}

private actor ImportReviewRepository: LedgerRepository {
    let ledger: Ledger
    init(ledger: Ledger) { self.ledger = ledger }
    func loadOrCreate() async throws -> Ledger { ledger }
    func save(_ ledger: Ledger) async throws {}
}
