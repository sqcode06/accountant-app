import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

struct DataProtectionTests {
    @MainActor
    @Test func retryAndRelaunchKeepDamagedDataProtected() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger()

        let state = files.makeAppState()
        await state.loadIfNeeded()
        #expect(state.isDataLocked)
        let record = try #require(state.dataProtection.quarantined.first)

        await state.retryLoadAfterDamage()
        #expect(state.isDataLocked)
        #expect(await state.createAccount(name: "Must not save", kind: .asset) == false)

        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(relaunched.isDataLocked)
        #expect(try Data(contentsOf: record.quarantinedURL) == files.damagedBytes)
        #expect(!FileManager.default.fileExists(atPath: files.ledgerURL.path))
    }

    @MainActor
    @Test(arguments: 1...7)
    func startFreshClearsLedgerBudgetAndRulesAndKeepsOriginal(damagedStores: Int) async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger(damagedStores: damagedStores)
        let state = files.makeAppState()
        await state.loadIfNeeded()
        let records = state.dataProtection.quarantined
        #expect(records.count == damagedStores.nonzeroBitCount)

        #expect(await state.startFreshAfterDamage())
        #expect(!state.isDataLocked)

        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(!relaunched.isDataLocked)
        #expect(relaunched.ledger.accounts.isEmpty)
        #expect(relaunched.ledger.transactions.isEmpty)
        #expect(relaunched.budget.targets.isEmpty)
        #expect(relaunched.classificationRules.isEmpty)
        for record in records {
            #expect(try Data(contentsOf: record.quarantinedURL) == files.damagedBytes)
        }
    }

    @MainActor
    @Test func failedStartFreshKeepsRecoveryLockedAcrossRelaunch() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger()
        let state = files.makeAppState(budgetRepository: FailingRecoveryBudgetRepository())
        await state.loadIfNeeded()
        let record = try #require(state.dataProtection.quarantined.first)

        #expect(await state.startFreshAfterDamage() == false)
        #expect(state.isDataLocked)
        #expect(state.lastError != nil)
        #expect(await state.flushPendingWrites() == false)

        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(relaunched.isDataLocked)
        #expect(relaunched.budget.targets.count == 1)
        #expect(relaunched.classificationRules.count == 1)
        #expect(try Data(contentsOf: record.quarantinedURL) == files.damagedBytes)

        // A deliberate retry through Start fresh can complete the reset. An
        // ordinary load or delayed save must never complete it implicitly.
        #expect(await relaunched.startFreshAfterDamage())
        let finished = files.makeAppState()
        await finished.loadIfNeeded()
        #expect(!finished.isDataLocked)
        #expect(finished.budget.targets.isEmpty)
        #expect(finished.classificationRules.isEmpty)
    }

    @MainActor
    @Test func failedRecoveryCompletionDoesNotDismissProtection() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger()
        let state = AppState(
            repository: FailingRecoveryCompletionRepository(base: files.ledgerRepository),
            classificationRuleRepository: files.ruleRepository,
            budgetRepository: files.budgetRepository
        )
        await state.loadIfNeeded()

        #expect(await state.startFreshAfterDamage() == false)
        #expect(state.isDataLocked)
        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(relaunched.isDataLocked)
    }

    @MainActor
    @Test func restoringBackupResolvesRecoveryOnlyAfterAllStoresAreSaved() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        let backup = try files.makeBackup()
        try files.seedThenDamageLedger()
        let state = files.makeAppState()
        await state.loadIfNeeded()
        let record = try #require(state.dataProtection.quarantined.first)

        #expect(await state.restore(from: backup))
        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(!relaunched.isDataLocked)
        #expect(relaunched.ledger == backup.ledger)
        #expect(relaunched.budget == backup.budget)
        #expect(relaunched.classificationRules == backup.classificationRules)
        #expect(try Data(contentsOf: record.quarantinedURL) == files.damagedBytes)
    }

    @MainActor
    @Test func invalidBackupCannotUnlockRecoveryOrWriteReplacement() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger()
        let state = files.makeAppState()
        await state.loadIfNeeded()
        let invalid = LedgerBackup(formatVersion: 999, ledger: Ledger())

        #expect(await state.restore(from: invalid) == false)
        #expect(state.isDataLocked)
        #expect(!FileManager.default.fileExists(atPath: files.ledgerURL.path))
        #expect(state.budget.targets.count == 1)
    }

    @MainActor
    @Test func semanticallyInvalidBackupCannotChangeLiveData() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        let valid = try files.makeBackup()
        try JSONLedgerStore(fileURL: files.ledgerURL).save(valid.ledger)
        let state = files.makeAppState()
        await state.loadIfNeeded()
        let bytesBefore = try Data(contentsOf: files.ledgerURL)
        // This is a supported format, but the budget's accounts are absent.
        let invalid = LedgerBackup(ledger: Ledger(), budget: valid.budget)

        #expect(await state.restore(from: invalid) == false)
        #expect(state.ledger == valid.ledger)
        #expect(try Data(contentsOf: files.ledgerURL) == bytesBefore)
        #expect(state.lastError != nil)
    }

    @MainActor
    @Test func recoveryRejectsConcurrentEditsAndReplacements() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger()
        let gate = GatedRecoveryLedgerRepository()
        let state = AppState(
            repository: GatedReplacementRepository(base: files.ledgerRepository, gate: gate),
            classificationRuleRepository: files.ruleRepository,
            budgetRepository: files.budgetRepository
        )
        await state.loadIfNeeded()
        let backup = try files.makeBackup()
        let replacement = Task { await state.startFreshAfterDamage() }
        try #require(await gate.waitUntilSaveStarts(1))

        #expect(state.isDataLocked)
        #expect(await state.createAccount(name: "Must not interleave", kind: .asset) == false)
        #expect(await state.restore(from: backup) == false)
        #expect(await state.startFreshAfterDamage() == false)
        #expect(await state.flushPendingWrites() == false)
        await state.retryLoadAfterDamage()
        #expect(state.isDataLocked)

        await gate.releaseSave()
        #expect(await replacement.value)
        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(!relaunched.isDataLocked)
        #expect(relaunched.ledger.accounts.isEmpty)
        #expect(relaunched.budget.targets.isEmpty)
        #expect(relaunched.classificationRules.isEmpty)
    }

    @MainActor
    @Test func failedRuleReplacementKeepsRestoredDataLocked() async throws {
        let files = try RecoveryFiles()
        defer { files.remove() }
        try files.seedThenDamageLedger()
        let state = AppState(
            repository: files.ledgerRepository,
            classificationRuleRepository: FailingRecoveryRuleRepository(base: files.ruleRepository),
            budgetRepository: files.budgetRepository
        )
        await state.loadIfNeeded()
        let record = try #require(state.dataProtection.quarantined.first)
        let backup = try files.makeBackup()

        #expect(await state.restore(from: backup) == false)
        #expect(state.isDataLocked)
        let relaunched = files.makeAppState()
        await relaunched.loadIfNeeded()
        #expect(relaunched.isDataLocked)
        #expect(try Data(contentsOf: record.quarantinedURL) == files.damagedBytes)
    }

    @MainActor
    @Test func concurrentFlushWaitsForChangesMadeDuringAnEarlierSave() async throws {
        let repository = GatedRecoveryLedgerRepository()
        let state = AppState(repository: repository)
        #expect(await state.createAccount(name: "First", kind: .asset))
        let first = Task { await state.flushPendingWrites() }
        try #require(await repository.waitUntilSaveStarts(1))

        #expect(await state.createAccount(name: "Second", kind: .asset))
        let entered = RecoveryTestSignal()
        let second = Task { @MainActor in
            entered.signal()
            let saved = await state.flushPendingWrites()
            return (saved, await repository.completedSaves)
        }
        await entered.wait()
        // Permits work even before the next save begins. If draining regresses,
        // the assertions below fail instead of waiting forever for save #2.
        await repository.releaseSave()
        await repository.releaseSave()

        #expect(await first.value)
        let (saved, savesAtReturn) = await second.value
        #expect(saved)
        #expect(savesAtReturn == 2)
        #expect(await repository.stored.accounts.count == 2)
    }

    @MainActor
    @Test func concurrentFlushReportsWriteFailureToEveryCallerAndCanRetry() async throws {
        let repository = GatedRecoveryLedgerRepository(failFirstSave: true)
        let state = AppState(repository: repository)
        #expect(await state.createAccount(name: "Keep this change", kind: .asset))
        let first = Task { await state.flushPendingWrites() }
        try #require(await repository.waitUntilSaveStarts(1))
        let entered = RecoveryTestSignal()
        let second = Task { @MainActor in
            entered.signal()
            return await state.flushPendingWrites()
        }
        await entered.wait()
        await repository.releaseSave()
        #expect(await first.value == false)
        #expect(await second.value == false)
        #expect(state.lastError != nil)
        #expect(state.ledger.accounts.count == 1)

        await repository.releaseSave()
        let retry = Task { await state.flushPendingWrites() }
        #expect(await retry.value)
        #expect(state.lastError == nil)
        #expect(await repository.stored.accounts.count == 1)
    }
}

private struct RecoveryFiles {
    let directory: URL
    let damagedBytes = Data("original damaged ledger: preserve these bytes".utf8)
    var ledgerURL: URL { directory.appendingPathComponent("ledger.json") }
    var budgetURL: URL { directory.appendingPathComponent("budget.json") }
    var rulesURL: URL { directory.appendingPathComponent("classification-rules.json") }
    var ledgerRepository: LocalJSONLedgerRepository { .init(fileURL: ledgerURL) }
    var budgetRepository: LocalJSONBudgetRepository { .init(fileURL: budgetURL) }
    var ruleRepository: LocalJSONClassificationRuleRepository { .init(fileURL: rulesURL) }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-recovery-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func makeBackup() throws -> LedgerBackup {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let category = Account(name: "Eating out", kind: .expense)
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(category)
        var budget = Budget()
        try budget.setTarget(
            amount: Money(20, currency: eur), for: category.id,
            from: BudgetPeriod(year: 2026, month: 9), in: ledger
        )
        return LedgerBackup(
            ledger: ledger, budget: budget,
            classificationRules: [ClassificationRuleConfiguration(
                needle: "CAFE", counterpartyAccountID: category.id, cleanedMemo: "Cafe"
            )]
        )
    }

    func seedThenDamageLedger(damagedStores: Int = 1) throws {
        let backup = try makeBackup()
        try JSONLedgerStore(fileURL: ledgerURL).save(backup.ledger)
        try JSONFileStore(fileURL: budgetURL) { Budget() }.save(backup.budget)
        try JSONFileStore(fileURL: rulesURL) { [ClassificationRuleConfiguration]() }
            .save(backup.classificationRules)
        for (offset, url) in [ledgerURL, budgetURL, rulesURL].enumerated()
            where damagedStores & (1 << offset) != 0 {
            try damagedBytes.write(to: url)
        }
    }

    @MainActor
    func makeAppState(budgetRepository: (any BudgetRepository)? = nil) -> AppState {
        AppState(
            repository: ledgerRepository,
            classificationRuleRepository: ruleRepository,
            budgetRepository: budgetRepository ?? self.budgetRepository
        )
    }
}

private enum RecoveryTestError: Error { case writeFailed }

private struct FailingRecoveryBudgetRepository: BudgetRepository {
    func loadOrCreate() async throws -> Budget { Budget() }
    func save(_ budget: Budget) async throws { throw RecoveryTestError.writeFailed }
}

private struct FailingRecoveryCompletionRepository: LedgerRepository {
    let base: LocalJSONLedgerRepository
    func loadOrCreate() async throws -> Ledger { try await base.loadOrCreate() }
    func load() async -> LedgerLoadOutcome { await base.load() }
    func save(_ ledger: Ledger) async throws { try await base.save(ledger) }
    func replaceForRecovery(_ ledger: Ledger) async throws { try await base.replaceForRecovery(ledger) }
    func completeRecovery() async throws { throw RecoveryTestError.writeFailed }
}

private struct GatedReplacementRepository: LedgerRepository {
    let base: LocalJSONLedgerRepository
    let gate: GatedRecoveryLedgerRepository
    func loadOrCreate() async throws -> Ledger { try await base.loadOrCreate() }
    func load() async -> LedgerLoadOutcome { await base.load() }
    func save(_ ledger: Ledger) async throws { try await base.save(ledger) }
    func replaceForRecovery(_ ledger: Ledger) async throws {
        try await gate.save(ledger)
        try await base.replaceForRecovery(ledger)
    }
    func completeRecovery() async throws { try await base.completeRecovery() }
}

private struct FailingRecoveryRuleRepository: ClassificationRuleRepository {
    let base: LocalJSONClassificationRuleRepository
    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] {
        try await base.loadOrCreate()
    }
    func save(_ rules: [ClassificationRuleConfiguration]) async throws {
        throw RecoveryTestError.writeFailed
    }
}

@MainActor
private final class RecoveryTestSignal {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?
    func signal() {
        signalled = true
        waiter?.resume()
        waiter = nil
    }
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor GatedRecoveryLedgerRepository: LedgerRepository {
    private(set) var stored = Ledger()
    private(set) var completedSaves = 0
    private var startedSaves = 0
    private var startWaiters: [UUID: (Int, CheckedContinuation<Bool, Never>)] = [:]
    private var gate: CheckedContinuation<Void, Never>?
    private var permits = 0
    private let failFirstSave: Bool

    init(failFirstSave: Bool = false) { self.failFirstSave = failFirstSave }
    func loadOrCreate() async throws -> Ledger { stored }

    func save(_ ledger: Ledger) async throws {
        startedSaves += 1
        let saveNumber = startedSaves
        if permits > 0 {
            permits -= 1
            notifySaveStarted()
        } else {
            await withCheckedContinuation { continuation in
                gate = continuation
                notifySaveStarted()
            }
        }
        if failFirstSave && saveNumber == 1 { throw RecoveryTestError.writeFailed }
        stored = ledger
        completedSaves += 1
    }

    func waitUntilSaveStarts(_ count: Int) async -> Bool {
        if startedSaves >= count { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            startWaiters[id] = (count, continuation)
            Task {
                try? await Task.sleep(for: .seconds(5))
                self.expireWaiter(id)
            }
        }
    }

    private func notifySaveStarted() {
        let ready = startWaiters.filter { $0.value.0 <= startedSaves }
        for (id, waiter) in ready {
            startWaiters[id] = nil
            waiter.1.resume(returning: true)
        }
    }

    private func expireWaiter(_ id: UUID) {
        startWaiters.removeValue(forKey: id)?.1.resume(returning: false)
    }

    func releaseSave() {
        if let gate {
            self.gate = nil
            gate.resume()
        } else {
            permits += 1
        }
    }
}
