import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

struct SnapshotReplacementTests {
    /// REL-04: this assertion failed against the old three-write restore with
    /// only the budget save failing (see docs/AppReliabilityPlan.md).
    @MainActor
    @Test(arguments: [false, true], [AppDataStore.Checkpoint.beforeEncoding, .beforeCommit, .afterCommit])
    func failedRestoreMustNotReloadMixedFinancialData(erasing: Bool, point: AppDataStore.Checkpoint) async throws {
        let files = try SnapshotFiles()
        defer { files.remove() }
        let old = try makeSnapshot("Old")
        let replacement = erasing ? LedgerBackup(ledger: Ledger()) : try makeSnapshot("Restored")
        try files.store.save(old)
        let failing = AppDataStore(directory: files.directory) { checkpoint in
            if checkpoint == point { throw SnapshotTestError.writeFailed }
        }
        let state = AppState(dataRepository: LocalJSONAppDataRepository(store: failing))
        await state.loadIfNeeded()
        let succeeded = erasing ? await state.eraseAllData() : await state.restore(from: replacement)
        #expect(!succeeded)
        #expect(state.lastError != nil)

        let expected = point == .afterCommit ? replacement : old
        let reopened = files.makeState()
        await reopened.loadIfNeeded()
        expectState(reopened, equals: expected)
        #expect(!reopened.isDataLocked)
        expectState(state, equals: expected)
        // Failure never leaves a destructive replacement queued for a later
        // background flush. The previous full snapshot remains authoritative.
        #expect(await state.flushPendingWrites())
        expectData(files.store.load().data, equals: expected)
    }

    @MainActor
    @Test(arguments: [false, true])
    func replacementWaitsForOlderWriterAndPreventsResurrection(failOlderSave: Bool) async throws {
        let files = try SnapshotFiles()
        defer { files.remove() }
        let original = try makeSnapshot("Original")
        try files.store.save(original)
        let repository = GatedSnapshotRepository(base: files.repository, failFirstSave: failOlderSave)
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()
        #expect(await state.createAccount(name: "Pending before erase", kind: .asset))
        let earlier = Task { await state.flushPendingWrites() }
        try #require(await repository.waitForSave(1))

        let entered = SnapshotSignal()
        let erase = Task { @MainActor in
            entered.signal()
            return await state.eraseAllData()
        }
        await entered.wait()
        #expect(await state.createAccount(name: "Must not interleave", kind: .asset) == false)
        #expect(await state.restore(from: original) == false)
        #expect(await state.eraseAllData() == false)
        #expect(await state.flushPendingWrites() == false)
        #expect(await repository.started == 1)

        await repository.release()
        try #require(await repository.waitForSave(2))
        // Even with the prior save complete, erase has not been acknowledged or
        // published while its own commit is blocked.
        #expect(state.ledger.accounts.values.contains { $0.name == "Pending before erase" })
        #expect(await repository.completed == (failOlderSave ? 0 : 1))
        await repository.release()
        #expect(await earlier.value == !failOlderSave)
        #expect(await erase.value)
        expectState(state, equals: LedgerBackup(ledger: Ledger()))
        #expect(await state.flushPendingWrites())
        #expect(await repository.started == 2)
        expectData(files.store.load().data, equals: LedgerBackup(ledger: Ledger()))
    }

    @MainActor
    @Test func failedReplacementPreservesUnsavedEditsWithoutRetryingErase() async throws {
        let files = try SnapshotFiles()
        defer { files.remove() }
        let original = try makeSnapshot("Original")
        try files.store.save(original)
        let repository = GatedSnapshotRepository(base: files.repository, failFirstSave: true)
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()
        #expect(await state.createAccount(name: "Keep this unsaved edit", kind: .asset))
        let erase = Task { await state.eraseAllData() }
        try #require(await repository.waitForSave(1))
        await repository.release()
        #expect(await erase.value == false)
        #expect(state.ledger.accounts.values.contains { $0.name == "Keep this unsaved edit" })
        expectData(files.store.load().data, equals: original)

        let retryOrdinaryEdits = Task { await state.flushPendingWrites() }
        try #require(await repository.waitForSave(2))
        await repository.release()
        #expect(await retryOrdinaryEdits.value)
        let reloaded = files.store.load()
        #expect(reloaded.data.ledger.accounts.values.contains { $0.name == "Keep this unsaved edit" })
        #expect(reloaded.data.budget == original.budget)
        #expect(reloaded.data.classificationRules == original.classificationRules)
    }

    @MainActor
    @Test func editsDuringSaveDrainAsCompleteSnapshotsForEveryFlushCaller() async throws {
        let files = try SnapshotFiles()
        defer { files.remove() }
        let original = try makeSnapshot("Original")
        try files.store.save(original)
        let repository = GatedSnapshotRepository(base: files.repository)
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()
        #expect(await state.createAccount(name: "First edit", kind: .asset))
        let first = Task { await state.flushPendingWrites() }
        try #require(await repository.waitForSave(1))
        let category = try #require(original.ledger.accounts.values.first)
        let budgetEntered = SnapshotSignal()
        let budgetSave = Task { @MainActor in
            budgetEntered.signal()
            return await state.setBudgetTarget(amount: Money(45, currency: Currency("EUR")),
                for: category.id, from: BudgetPeriod(year: 2026, month: 9))
        }
        await budgetEntered.wait()
        #expect(state.hasUnsavedChanges)
        let entered = SnapshotSignal()
        let second = Task { @MainActor in
            entered.signal()
            return await state.flushPendingWrites()
        }
        await entered.wait()
        await repository.release()
        try #require(await repository.waitForSave(2))
        #expect(files.store.load().data.budget == original.budget)
        await repository.release()
        #expect(await first.value)
        #expect(await second.value)
        #expect(await budgetSave.value)
        #expect(!state.hasUnsavedChanges)
        let latest = files.store.load()
        #expect(latest.data.ledger == state.ledger)
        #expect(latest.data.budget == state.budget)
        #expect(latest.data.classificationRules == state.classificationRules)
        #expect(latest.damage.isEmpty)
    }

    @MainActor
    @Test(arguments: AppDataStore.Checkpoint.allCases)
    func interruptedRecoveryRequiresACompleteSnapshotOrProtection(point: AppDataStore.Checkpoint) async throws {
        let files = try SnapshotFiles()
        defer { files.remove() }
        let original = try makeSnapshot("Original")
        try files.store.save(original)
        let broken = Data("keep damaged snapshot bytes".utf8)
        try broken.write(to: files.directory.appendingPathComponent("ledger.json"))
        let repository = LocalJSONAppDataRepository(store: AppDataStore(directory: files.directory) { checkpoint in
            if checkpoint == point { throw SnapshotTestError.writeFailed }
        })
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()
        let record = try #require(state.dataProtection.quarantined.first)
        let replacement = try makeSnapshot("Restored")
        #expect(await state.restore(from: replacement) == false)
        let reopened = files.makeState()
        await reopened.loadIfNeeded()
        if point == .afterRecoveryCompletion {
            #expect(!reopened.isDataLocked)
            expectState(reopened, equals: replacement)
            expectState(state, equals: replacement)
        } else {
            #expect(reopened.isDataLocked)
            #expect(state.isDataLocked)
            #expect(await reopened.createAccount(name: "Must not save", kind: .asset) == false)
            #expect(await reopened.flushPendingWrites() == false)
        }
        #expect(try Data(contentsOf: record.quarantinedURL) == broken)
        if reopened.isDataLocked { #expect(await reopened.restore(from: replacement)) }
        let final = files.makeState()
        await final.loadIfNeeded()
        #expect(!final.isDataLocked)
        expectState(final, equals: replacement)
    }

    @MainActor
    @Test func malformedRestoreNeverCallsRepositoryOrChangesData() async throws {
        let files = try SnapshotFiles()
        defer { files.remove() }
        let original = try makeSnapshot("Original")
        try files.store.save(original)
        let repository = GatedSnapshotRepository(base: files.repository)
        let state = AppState(dataRepository: repository)
        await state.loadIfNeeded()
        let invalid = LedgerBackup(ledger: Ledger(), budget: original.budget)
        #expect(await state.restore(from: invalid) == false)
        #expect(await repository.started == 0)
        expectState(state, equals: original)
        expectData(files.store.load().data, equals: original)
    }
}

private struct SnapshotFiles {
    let directory: URL
    var store: AppDataStore { AppDataStore(directory: directory) }
    var repository: LocalJSONAppDataRepository { LocalJSONAppDataRepository(directory: directory) }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    @MainActor func makeState() -> AppState { AppState(dataRepository: repository) }
}

private func makeSnapshot(_ name: String) throws -> LedgerBackup {
    let category = Account(name: name, kind: .expense)
    var ledger = Ledger()
    ledger.addAccount(category)
    var budget = Budget()
    try budget.setTarget(amount: Money(20, currency: Currency("EUR")), for: category.id,
                         from: BudgetPeriod(year: 2026, month: 9), in: ledger)
    return LedgerBackup(ledger: ledger, budget: budget, classificationRules: [
        ClassificationRuleConfiguration(needle: name, counterpartyAccountID: category.id)
    ])
}

@MainActor
private func expectState(_ state: AppState, equals expected: LedgerBackup, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(state.ledger == expected.ledger, sourceLocation: sourceLocation)
    #expect(state.budget == expected.budget, sourceLocation: sourceLocation)
    #expect(state.classificationRules == expected.classificationRules, sourceLocation: sourceLocation)
}

private func expectData(_ actual: LedgerBackup, equals expected: LedgerBackup, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual.ledger == expected.ledger, sourceLocation: sourceLocation)
    #expect(actual.budget == expected.budget, sourceLocation: sourceLocation)
    #expect(actual.classificationRules == expected.classificationRules, sourceLocation: sourceLocation)
}

private enum SnapshotTestError: Error { case writeFailed }

@MainActor
private final class SnapshotSignal {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?
    func signal() { signalled = true; waiter?.resume(); waiter = nil }
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor GatedSnapshotRepository: AppDataRepository {
    let base: LocalJSONAppDataRepository
    let failFirstSave: Bool
    private(set) var started = 0
    private(set) var completed = 0
    private var permits = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var waiters: [UUID: (Int, CheckedContinuation<Bool, Never>)] = [:]

    init(base: LocalJSONAppDataRepository, failFirstSave: Bool = false) {
        self.base = base
        self.failFirstSave = failFirstSave
    }
    func load() async -> AppDataLoadResult { await base.load() }
    func save(_ data: LedgerBackup) async throws {
        started += 1
        let number = started
        if permits > 0 { permits -= 1; notify() }
        else { await withCheckedContinuation { gate = $0; notify() } }
        if failFirstSave && number == 1 { throw SnapshotTestError.writeFailed }
        try await base.save(data)
        completed += 1
    }
    func release() {
        if let gate { self.gate = nil; gate.resume() }
        else { permits += 1 }
    }
    func waitForSave(_ number: Int) async -> Bool {
        if started >= number { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = (number, continuation)
            // A bounded failure timeout, never the synchronization mechanism.
            Task { try? await Task.sleep(for: .seconds(5)); expire(id) }
        }
    }
    private func notify() {
        for (id, waiter) in waiters where waiter.0 <= started {
            waiters.removeValue(forKey: id)?.1.resume(returning: true)
        }
    }
    private func expire(_ id: UUID) { waiters.removeValue(forKey: id)?.1.resume(returning: false) }
}
