import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

struct AccountantAppTests {

    @MainActor
    @Test func loadIfNeededLoadsLedgerOnlyOnce() async throws {
        let bank = Account(name: "Bank", kind: .asset)
        var ledger = Ledger()
        ledger.addAccount(bank)

        let repository = InMemoryLedgerRepository(ledger: ledger)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()
        await appState.loadIfNeeded()

        #expect(await repository.loadCallCount == 1)
        #expect(appState.ledger.accounts[bank.id]?.name == "Bank")
        #expect(appState.lastError == nil)
    }

    @MainActor
    @Test func loadFailureUsesEmptyLedgerAndReportsError() async throws {
        let repository = InMemoryLedgerRepository(loadError: TestRepositoryError.loadFailed)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        #expect(appState.ledger.accounts.isEmpty)
        #expect(appState.lastError?.message.isEmpty == false)
    }

    @MainActor
    @Test func createAccountTrimsNameAndSaves() async throws {
        let repository = InMemoryLedgerRepository()
        let appState = AppState(repository: repository)

        let success = await appState.createAccount(name: "  Bank  ", kind: .asset)

        #expect(success)
        #expect(appState.ledger.accounts.values.first?.name == "Bank")
        #expect(appState.ledger.accounts.values.first?.kind == .asset)
        #expect(await repository.savedLedgers.count == 1)
        #expect(appState.lastError == nil)
    }

    @MainActor
    @Test func createAccountRejectsEmptyNameWithoutSaving() async throws {
        let repository = InMemoryLedgerRepository()
        let appState = AppState(repository: repository)

        let success = await appState.createAccount(name: "   ", kind: .asset)

        #expect(!success)
        #expect(appState.ledger.accounts.isEmpty)
        #expect(await repository.savedLedgers.isEmpty)
        #expect(appState.lastError?.message == "Account name cannot be empty.")
    }

    @MainActor
    @Test func renameAccountUpdatesVisibleLedgerAndSaves() async throws {
        let bank = Account(name: "Old Bank", kind: .asset)
        let repository = InMemoryLedgerRepository(ledger: ledger(with: [bank]))
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()
        let success = await appState.renameAccount(id: bank.id, to: "  New Bank  ")

        #expect(success)
        #expect(appState.ledger.accounts[bank.id]?.name == "New Bank")
        #expect(await repository.savedLedgers.count == 1)
    }

    @MainActor
    @Test func archiveAndRestoreAccountRoundTrip() async throws {
        let bank = Account(name: "Bank", kind: .asset)
        let repository = InMemoryLedgerRepository(ledger: ledger(with: [bank]))
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let archived = await appState.archiveAccount(id: bank.id)
        #expect(archived)
        #expect(appState.ledger.accounts[bank.id]?.status == .archived)

        let restored = await appState.restoreAccount(id: bank.id)
        #expect(restored)
        #expect(appState.ledger.accounts[bank.id]?.status == .active)
        #expect(await repository.savedLedgers.count == 2)
    }

    @MainActor
    @Test func failedSaveDoesNotMutateVisibleAccountState() async throws {
        let repository = InMemoryLedgerRepository(saveError: TestRepositoryError.saveFailed)
        let appState = AppState(repository: repository)

        let success = await appState.createAccount(name: "Bank", kind: .asset)

        #expect(!success)
        #expect(appState.ledger.accounts.isEmpty)
        #expect(await repository.savedLedgers.isEmpty)
        #expect(appState.lastError?.message.isEmpty == false)
    }

    @MainActor
    @Test func createDraftExpenseCreatesDraftTransactionAndSaves() async throws {
        let fixture = TransactionFixture()
        let repository = InMemoryLedgerRepository(ledger: fixture.ledger)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let success = await appState.createDraftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: fixture.money(42),
            date: fixture.date,
            memo: "  Rimi  "
        )

        let transaction = onlyTransaction(in: appState)

        #expect(success)
        #expect(transaction?.state == .draft)
        #expect(transaction?.memo == "Rimi")
        #expect(transaction?.postings.count == 2)
        #expect(await repository.savedLedgers.count == 1)
    }

    @MainActor
    @Test func createFinalizedIncomeCreatesFinalizedTransactionAndSaves() async throws {
        let fixture = TransactionFixture()
        let repository = InMemoryLedgerRepository(ledger: fixture.ledger)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let success = await appState.createFinalizedIncome(
            receivedIn: fixture.bank.id,
            source: fixture.salary.id,
            amount: fixture.money(1000),
            date: fixture.date,
            memo: "Salary"
        )

        let transaction = onlyTransaction(in: appState)

        #expect(success)
        #expect(transaction?.state == .finalized)
        #expect(transaction?.finalizedAt != nil)
        #expect(transaction?.memo == "Salary")
        #expect(await repository.savedLedgers.count == 1)
    }

    @MainActor
    @Test func createDraftTransferCreatesDraftTransactionAndSaves() async throws {
        let fixture = TransactionFixture()
        let repository = InMemoryLedgerRepository(ledger: fixture.ledger)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let success = await appState.createDraftTransfer(
            from: fixture.bank.id,
            to: fixture.savings.id,
            amount: fixture.money(250),
            date: fixture.date,
            memo: nil
        )

        let transaction = onlyTransaction(in: appState)

        #expect(success)
        #expect(transaction?.state == .draft)
        #expect(transaction?.memo == nil)
        #expect(transaction?.postings.count == 2)
        #expect(await repository.savedLedgers.count == 1)
    }

    @MainActor
    @Test func finalizeTransactionUpdatesExistingDraftAndSaves() async throws {
        let fixture = TransactionFixture()
        var initialLedger = fixture.ledger
        let draft = try Transaction.draftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: fixture.money(12),
            date: fixture.date,
            memo: "Coffee"
        )
        try initialLedger.addTransaction(draft)

        let repository = InMemoryLedgerRepository(ledger: initialLedger)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let success = await appState.finalizeTransaction(id: draft.id)
        let transaction = onlyTransaction(in: appState)

        #expect(success)
        #expect(transaction?.state == .finalized)
        #expect(transaction?.finalizedAt != nil)
        #expect(await repository.savedLedgers.count == 1)
    }

    @MainActor
    @Test func nonPositiveAmountReportsUserFacingError() async throws {
        let fixture = TransactionFixture()
        let repository = InMemoryLedgerRepository(ledger: fixture.ledger)
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let success = await appState.createDraftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: fixture.money(0),
            date: fixture.date,
            memo: nil
        )

        #expect(!success)
        #expect(appState.ledger.allTransactionsSorted(includeDrafts: true).isEmpty)
        #expect(appState.lastError?.message == "Amount must be greater than zero.")
    }

    @MainActor
    @Test func failedSaveDoesNotExposeUnsavedTransaction() async throws {
        let fixture = TransactionFixture()
        let repository = InMemoryLedgerRepository(
            ledger: fixture.ledger,
            saveError: TestRepositoryError.saveFailed
        )
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()

        let success = await appState.createDraftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: fixture.money(42),
            date: fixture.date,
            memo: "Rimi"
        )

        #expect(!success)
        #expect(appState.ledger.allTransactionsSorted(includeDrafts: true).isEmpty)
        #expect(await repository.savedLedgers.isEmpty)
        #expect(appState.lastError?.message.isEmpty == false)
    }
}

private enum TestRepositoryError: Error {
    case loadFailed
    case saveFailed
}

private actor InMemoryLedgerRepository: LedgerRepository {
    private var storedLedger: Ledger
    private let loadError: Error?
    private let saveError: Error?

    private(set) var loadCallCount = 0
    private(set) var savedLedgers: [Ledger] = []

    init(
        ledger: Ledger = Ledger(),
        loadError: Error? = nil,
        saveError: Error? = nil
    ) {
        self.storedLedger = ledger
        self.loadError = loadError
        self.saveError = saveError
    }

    func loadOrCreate() async throws -> Ledger {
        loadCallCount += 1

        if let loadError {
            throw loadError
        }

        return storedLedger
    }

    func save(_ ledger: Ledger) async throws {
        if let saveError {
            throw saveError
        }

        storedLedger = ledger
        savedLedgers.append(ledger)
    }
}

private struct TransactionFixture {
    let currency = Currency("EUR")
    let date = Date(timeIntervalSinceReferenceDate: 750_000_000)

    let bank = Account(name: "Bank", kind: .asset)
    let savings = Account(name: "Savings", kind: .asset)
    let groceries = Account(name: "Groceries", kind: .expense)
    let salary = Account(name: "Salary", kind: .income)

    var ledger: Ledger {
        ledger(with: [bank, savings, groceries, salary])
    }

    func money(_ amount: Decimal) -> Money {
        Money(amount, currency: currency)
    }
}

private func ledger(with accounts: [Account]) -> Ledger {
    var ledger = Ledger()

    for account in accounts {
        ledger.addAccount(account)
    }

    return ledger
}

@MainActor
private func onlyTransaction(in appState: AppState) -> AccountantCore.Transaction? {
    appState.ledger.allTransactionsSorted(includeDrafts: true).first
}
