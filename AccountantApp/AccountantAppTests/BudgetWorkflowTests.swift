import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

struct BudgetWorkflowTests {
    @MainActor
    @Test func monthlyLimitCountsADraftOnceAndSurvivesConfirmationAndReload() async throws {
        let eur = Currency("EUR")
        let august = BudgetPeriod(year: 2026, month: 8)
        let september = august.next
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let eatingOut = Account(name: "Eating out", kind: .expense)
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(eatingOut)

        let ledgerRepository = BudgetWorkflowLedgerRepository(ledger: ledger)
        let budgetRepository = BudgetWorkflowBudgetRepository()
        let appState = AppState(repository: ledgerRepository, budgetRepository: budgetRepository)
        await appState.loadIfNeeded()

        let saved = await appState.setBudgetTarget(
            amount: Money(20, currency: eur), for: eatingOut.id, from: august
        )
        #expect(saved)
        #expect(appState.budgetReport(for: september).totalRemaining.amount == 20)

        let purchaseDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 13, hour: 12)
        ))
        let captured = await appState.createDraftExpense(
            paidFrom: bank.id, category: eatingOut.id,
            amount: Money(Decimal(10) / 100, currency: eur),
            date: purchaseDate, memo: nil
        )
        #expect(captured)
        let transaction = try #require(appState.ledger.transactions.first)
        #expect(transaction.state == .draft)

        let draftReport = appState.budgetReport(for: september)
        #expect(draftReport.totalTarget.amount == 20)
        #expect(draftReport.totalSpent.amount == Decimal(10) / 100)
        #expect(draftReport.totalRemaining.amount == Decimal(1990) / 100)
        #expect(appState.budgetReport(for: august).totalSpent.amount == 0)

        let confirmed = await appState.confirmTransactions(ids: [transaction.id])
        #expect(confirmed)
        #expect(appState.budgetReport(for: september) == draftReport)

        // The monthly allowance repeats; September's spending does not.
        let octoberReport = appState.budgetReport(for: september.next)
        #expect(octoberReport.totalTarget.amount == 20)
        #expect(octoberReport.totalSpent.amount == 0)
        #expect(octoberReport.totalRemaining.amount == 20)

        await appState.flushPendingWrites()
        let reloaded = AppState(repository: ledgerRepository, budgetRepository: budgetRepository)
        await reloaded.loadIfNeeded()
        #expect(reloaded.budget == appState.budget)
        #expect(reloaded.budgetReport(for: september) == draftReport)
        #expect(reloaded.ledger.transactions.first?.state == .finalized)
    }
}

private actor BudgetWorkflowLedgerRepository: LedgerRepository {
    private var ledger: Ledger

    init(ledger: Ledger) { self.ledger = ledger }

    func loadOrCreate() async throws -> Ledger { ledger }
    func save(_ ledger: Ledger) async throws { self.ledger = ledger }
}

private actor BudgetWorkflowBudgetRepository: BudgetRepository {
    private var budget = Budget()

    func loadOrCreate() async throws -> Budget { budget }
    func save(_ budget: Budget) async throws { self.budget = budget }
}
