import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

struct BudgetDurabilityTests {
    @MainActor
    @Test(arguments: [false, true])
    func clearingTransactionsKeepsSavedBudgetAndRules(failFirstSave: Bool) async throws {
        let files = try BudgetDurabilityFiles(hasSpending: true)
        defer { files.remove() }
        let repository: any AppDataRepository = failFirstSave
            ? BudgetWriteFailureRepository(base: files.repository)
            : files.repository
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()

        #expect(await state.clearAllTransactions() == !failFirstSave)
        if failFirstSave {
            #expect(state.hasUnsavedChanges)
            #expect(state.lastError != nil)
            #expect(files.store.load().data.ledger == files.original.ledger)
            #expect(await state.flushPendingWrites())
        }
        #expect(!state.hasUnsavedChanges)
        let saved = files.store.load().data
        #expect(saved.ledger.transactions.isEmpty)
        #expect(saved.ledger.accounts == files.original.ledger.accounts)
        #expect(saved.budget == files.original.budget)
        #expect(saved.classificationRules == files.original.classificationRules)
    }

    @MainActor
    @Test(arguments: [false, true], [false, true])
    func acknowledgedStopSurvivesImmediateReload(startedThisMonth: Bool, hasSpending: Bool) async throws {
        let files = try BudgetDurabilityFiles(startedThisMonth: startedThisMonth, hasSpending: hasSpending)
        defer { files.remove() }
        let state = AppState(dataRepository: files.repository)
        await state.loadIfNeeded()

        #expect(await state.removeBudgetTarget(for: files.category.id, from: files.september))
        #expect(!state.hasUnsavedChanges)
        // No explicit flush, debounce sleep, or background event: success itself
        // must mean a new process can read the change.
        let saved = files.store.load().data
        #expect(saved.budget.target(for: files.category.id, in: files.september) == nil)
        #expect(saved.budget.target(for: files.category.id, in: files.september.next) == nil)
        // Stopping closes the target's end date; the historical limit and its
        // identity stay the same even though that recurrence metadata changes.
        #expect(saved.budget.target(for: files.category.id, in: files.august)?.amount
            == files.original.budget.target(for: files.category.id, in: files.august)?.amount)
        #expect(saved.budget.target(for: files.category.id, in: files.august)?.id
            == files.original.budget.target(for: files.category.id, in: files.august)?.id)
        #expect(saved.budget.target(for: files.other.id, in: files.september)
            == files.original.budget.target(for: files.other.id, in: files.september))
        #expect(saved.ledger == files.original.ledger)
        #expect(saved.classificationRules == files.original.classificationRules)
    }

    @MainActor
    @Test(arguments: BudgetSaveAction.allCases)
    func failedBudgetChangeReportsFailureAndRetriesWholeSnapshot(action: BudgetSaveAction) async throws {
        let files = try BudgetDurabilityFiles()
        defer { files.remove() }
        let repository = BudgetWriteFailureRepository(base: files.repository)
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()

        #expect(await action.apply(to: state, files: files) == false)
        #expect(state.lastError != nil)
        #expect(state.hasUnsavedChanges)
        #expect(state.budget != files.original.budget)
        #expect(files.store.load().data.budget == files.original.budget)

        // Retry saving the current state, not reapplying an old Stop action.
        #expect(await state.flushPendingWrites())
        #expect(state.lastError == nil)
        #expect(!state.hasUnsavedChanges)
        let saved = files.store.load().data
        #expect(saved.budget == state.budget)
        #expect(saved.ledger == files.original.ledger)
        #expect(saved.classificationRules == files.original.classificationRules)
    }
}

enum BudgetSaveAction: CaseIterable, Sendable {
    case set, stop, clear

    @MainActor
    fileprivate func apply(to state: AppState, files: BudgetDurabilityFiles) async -> Bool {
        switch self {
        case .set:
            await state.setBudgetTarget(amount: Money(45, currency: Currency("EUR")),
                for: files.category.id, from: files.september)
        case .stop:
            await state.removeBudgetTarget(for: files.category.id, from: files.september)
        case .clear:
            await state.clearBudget()
        }
    }
}

private struct BudgetDurabilityFiles {
    let directory: URL
    let category = Account(name: "Eating out", kind: .expense)
    let other = Account(name: "Groceries", kind: .expense)
    let august = BudgetPeriod(year: 2026, month: 8)
    let september = BudgetPeriod(year: 2026, month: 9)
    private(set) var original: LedgerBackup
    var store: AppDataStore { AppDataStore(directory: directory) }
    var repository: LocalJSONAppDataRepository { LocalJSONAppDataRepository(directory: directory) }

    init(startedThisMonth: Bool = false, hasSpending: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("budget-durability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bank = Account(name: "Bank", kind: .asset, currency: Currency("EUR"))
        var ledger = Ledger()
        for account in [bank, category, other] { ledger.addAccount(account) }
        if hasSpending {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 12))!
            let transaction = try Transaction.draftExpense(paidFrom: bank.id, category: category.id,
                amount: Money(5, currency: Currency("EUR")), date: date, memo: "Preserve this purchase")
            try ledger.addTransaction(transaction)
            try ledger.finalizeTransaction(id: transaction.id)
        }
        var budget = Budget()
        try budget.setTarget(amount: Money(20, currency: Currency("EUR")), for: category.id,
            from: startedThisMonth ? september : august, in: ledger)
        try budget.setTarget(amount: Money(30, currency: Currency("EUR")), for: other.id, from: august, in: ledger)
        original = LedgerBackup(ledger: ledger, budget: budget, classificationRules: [
            ClassificationRuleConfiguration(needle: "Cafe", counterpartyAccountID: category.id)
        ])
        try store.save(original)
        // Compare against the persisted precision of transaction timestamps.
        original = store.load().data
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private enum BudgetWriteError: Error { case failed }

private actor BudgetWriteFailureRepository: AppDataRepository {
    let base: LocalJSONAppDataRepository
    private var shouldFail = true
    init(base: LocalJSONAppDataRepository) { self.base = base }
    func load() async -> AppDataLoadResult { await base.load() }
    func save(_ data: LedgerBackup) async throws {
        if shouldFail {
            shouldFail = false
            throw BudgetWriteError.failed
        }
        try await base.save(data)
    }
}
