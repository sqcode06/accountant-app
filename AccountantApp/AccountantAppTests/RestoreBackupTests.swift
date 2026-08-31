import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

/// Restoring a backup.
///
/// The property that matters is completeness. A restore that brings back the
/// transactions and quietly leaves the previous budget and rules in place would
/// look like it worked, and you would only find out weeks later when a limit you
/// deleted was still there.
struct RestoreBackupTests {

    private static let eur = Currency("EUR")

    private static func makeBackup() throws -> (
        backup: LedgerBackup,
        bank: Account,
        groceries: Account
    ) {
        var ledger = Ledger()
        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(25), currency: eur),
            date: Date(timeIntervalSince1970: 1_709_634_600),
            memo: "From the backup"
        )
        try ledger.addTransaction(tx)

        var budget = Budget()
        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: groceries.id,
            from: BudgetPeriod(year: 2024, month: 3),
            in: ledger
        )

        let rule = ClassificationRuleConfiguration(
            needle: "RIMI",
            counterpartyAccountID: groceries.id,
            cleanedMemo: "Rimi"
        )

        return (
            LedgerBackup(ledger: ledger, budget: budget, classificationRules: [rule]),
            bank,
            groceries
        )
    }

    @MainActor
    @Test func restoreReplacesLedgerBudgetAndRules() async throws {
        let (backup, _, _) = try Self.makeBackup()

        let ledgerRepository = RecordingLedgerRepository()
        let budgetRepository = RecordingBudgetRepository()
        let ruleRepository = RecordingRuleRepository()

        let appState = AppState(
            repository: ledgerRepository,
            classificationRuleRepository: ruleRepository,
            budgetRepository: budgetRepository
        )
        await appState.loadIfNeeded()

        // Something already there, so the restore has to displace it rather than
        // merely fill a vacuum.
        _ = await appState.createAccount(name: "Old account", kind: .asset)
        #expect(appState.ledger.accounts.count == 1)

        let restored = await appState.restore(from: backup)

        #expect(restored)
        #expect(appState.ledger.accounts.count == 2)
        #expect(appState.ledger.transactions.count == 1)
        #expect(appState.ledger.transactions.first?.memo == "From the backup")
        #expect(!appState.ledger.accounts.values.contains { $0.name == "Old account" })

        // The two halves a ledger-only restore would have missed.
        #expect(appState.budget.targets.count == 1)
        #expect(appState.classificationRules.count == 1)
        #expect(appState.classificationRules.first?.needle == "RIMI")
    }

    @MainActor
    @Test func restoreWritesAllThreeStores() async throws {
        let (backup, _, _) = try Self.makeBackup()

        let ledgerRepository = RecordingLedgerRepository()
        let budgetRepository = RecordingBudgetRepository()
        let ruleRepository = RecordingRuleRepository()

        let appState = AppState(
            repository: ledgerRepository,
            classificationRuleRepository: ruleRepository,
            budgetRepository: budgetRepository
        )
        await appState.loadIfNeeded()

        _ = await appState.restore(from: backup)

        // Flushed by the restore itself, not left sitting in the debounce window.
        #expect(await ledgerRepository.savedLedgers.last?.transactions.count == 1)
        #expect(await budgetRepository.saved.last?.targets.count == 1)
        #expect(await ruleRepository.saved.last?.count == 1)
    }

    /// The undo offer points into the ledger that was just replaced.
    @MainActor
    @Test func restoreClearsAPendingUndo() async throws {
        let (backup, _, _) = try Self.makeBackup()

        let appState = AppState(repository: RecordingLedgerRepository())
        await appState.loadIfNeeded()

        let bank = Account(name: "Bank", kind: .asset)
        let groceries = Account(name: "Groceries", kind: .expense)
        _ = await appState.createAccount(name: bank.name, kind: .asset)
        _ = await appState.createAccount(name: groceries.name, kind: .expense)

        let accounts = appState.ledger.accounts.values
        let asset = try #require(accounts.first { $0.kind == .asset })
        let category = try #require(accounts.first { $0.kind == .expense })

        _ = await appState.createDraftExpense(
            paidFrom: asset.id,
            category: category.id,
            amount: Money(Decimal(5), currency: Self.eur),
            date: Date(timeIntervalSince1970: 1_709_634_600),
            memo: "Doomed"
        )

        let draft = try #require(appState.ledger.transactions.first)
        _ = await appState.deleteDraftTransaction(id: draft.id)
        #expect(appState.recentlyDeletedDraft != nil)

        _ = await appState.restore(from: backup)

        // Undoing after a restore would insert a stranger into the restored data.
        #expect(appState.recentlyDeletedDraft == nil)
        #expect(await appState.undoDraftDeletion() == false)
        #expect(appState.ledger.transactions.count == 1)
        #expect(appState.ledger.transactions.first?.memo == "From the backup")
    }

    /// A damaged store is one of the main reasons anyone restores, so the
    /// data-protection lock must not block it.
    @MainActor
    @Test func restoreIsAllowedWhileDataIsLocked() async throws {
        let (backup, _, _) = try Self.makeBackup()

        let repository = UnreadableLedgerRepository()
        let appState = AppState(repository: repository)

        await appState.loadIfNeeded()
        #expect(appState.isDataLocked)

        // An ordinary write is refused while locked.
        #expect(await appState.createAccount(name: "Nope", kind: .asset) == false)

        let restored = await appState.restore(from: backup)

        #expect(restored)
        #expect(!appState.isDataLocked)
        #expect(appState.ledger.transactions.count == 1)
    }
}

// MARK: - Fixtures

private actor RecordingLedgerRepository: LedgerRepository {
    private var stored = Ledger()
    private(set) var savedLedgers: [Ledger] = []

    func loadOrCreate() async throws -> Ledger { stored }

    func save(_ ledger: Ledger) async throws {
        stored = ledger
        savedLedgers.append(ledger)
    }
}

private actor RecordingBudgetRepository: BudgetRepository {
    private(set) var saved: [Budget] = []

    func loadOrCreate() async throws -> Budget { Budget() }

    func save(_ budget: Budget) async throws {
        saved.append(budget)
    }
}

private actor RecordingRuleRepository: ClassificationRuleRepository {
    private(set) var saved: [[ClassificationRuleConfiguration]] = []

    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] { [] }

    func save(_ rules: [ClassificationRuleConfiguration]) async throws {
        saved.append(rules)
    }
}

/// Reports its file as unreadable, which is what puts AppState into its locked
/// state.
private actor UnreadableLedgerRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger { Ledger() }

    func load() async -> LedgerLoadOutcome {
        .unreadable(
            QuarantineRecord(
                originalURL: URL(fileURLWithPath: "/tmp/ledger.json"),
                quarantinedURL: URL(fileURLWithPath: "/tmp/ledger.unreadable.json"),
                reason: "test"
            )
        )
    }

    func save(_ ledger: Ledger) async throws {}
}
