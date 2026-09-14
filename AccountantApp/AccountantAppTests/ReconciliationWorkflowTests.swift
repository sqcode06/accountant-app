import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

struct ReconciliationWorkflowTests {
    private let eur = Currency("EUR")

    @MainActor
    @Test func clearingAndUnclearingPersistOnlyTheSelectedTransferAccount() async throws {
        let files = try ReconciliationFiles()
        defer { files.remove() }
        let fixture = try makeTransferFixture()
        try await files.repository.save(LedgerBackup(ledger: fixture.ledger))
        let state = files.makeState()
        await state.loadIfNeeded()

        #expect(await state.setCleared(true, forAccount: fixture.bank.id, in: fixture.transfer.id))
        #expect(clearedValues(in: state.ledger, transaction: fixture.transfer.id, account: fixture.bank.id) == [true])
        #expect(clearedValues(in: state.ledger, transaction: fixture.transfer.id, account: fixture.savings.id) == [false])
        #expect(state.hasUnsavedChanges)

        // The ordinary mutation is deliberately debounced; durability is explicit.
        let beforeFlush = AppDataStore(directory: files.directory).load().data.ledger
        #expect(clearedValues(in: beforeFlush, transaction: fixture.transfer.id, account: fixture.bank.id) == [false])
        #expect(await state.flushPendingWrites())
        #expect(!state.hasUnsavedChanges)

        let clearedRelaunch = files.makeState()
        await clearedRelaunch.loadIfNeeded()
        #expect(clearedValues(in: clearedRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.bank.id) == [true])
        #expect(clearedValues(in: clearedRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.savings.id) == [false])

        #expect(await clearedRelaunch.setCleared(false, forAccount: fixture.bank.id, in: fixture.transfer.id))
        #expect(await clearedRelaunch.flushPendingWrites())

        let unclearedRelaunch = files.makeState()
        await unclearedRelaunch.loadIfNeeded()
        #expect(clearedValues(in: unclearedRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.bank.id) == [false])
        #expect(clearedValues(in: unclearedRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.savings.id) == [false])
    }

    @MainActor
    @Test func unknownAccountAndTransactionIDsLeaveStateAndDiskUntouched() async throws {
        let files = try ReconciliationFiles()
        defer { files.remove() }
        let fixture = try makeTransferFixture()
        try await files.repository.save(LedgerBackup(ledger: fixture.ledger))
        let state = files.makeState()
        await state.loadIfNeeded()
        let original = state.ledger

        #expect(await state.setCleared(true, forAccount: AccountID(), in: fixture.transfer.id) == false)
        #expect(state.ledger == original)
        #expect(!state.hasUnsavedChanges)

        #expect(await state.setCleared(true, forAccount: fixture.bank.id, in: TransactionID()) == false)
        #expect(state.ledger == original)
        #expect(!state.hasUnsavedChanges)
        #expect(await state.flushPendingWrites())
        #expect(AppDataStore(directory: files.directory).load().data.ledger == original)
    }

    @MainActor
    @Test func failedFlushKeepsClearingVisibleAndPendingUntilRetryPersistsIt() async throws {
        let files = try ReconciliationFiles()
        defer { files.remove() }
        let fixture = try makeTransferFixture()
        try await files.repository.save(LedgerBackup(ledger: fixture.ledger))
        let fault = ReconciliationSaveFault()
        let state = files.makeState(fault: fault)
        await state.loadIfNeeded()
        fault.failNextCommit()

        #expect(await state.setCleared(true, forAccount: fixture.bank.id, in: fixture.transfer.id))
        #expect(state.hasUnsavedChanges)
        #expect(await state.flushPendingWrites() == false)
        #expect(clearedValues(in: state.ledger, transaction: fixture.transfer.id, account: fixture.bank.id) == [true])
        #expect(state.hasUnsavedChanges)
        #expect(state.lastError != nil)

        let failedRelaunch = files.makeState()
        await failedRelaunch.loadIfNeeded()
        #expect(clearedValues(in: failedRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.bank.id) == [false])

        #expect(await state.flushPendingWrites())
        #expect(!state.hasUnsavedChanges)
        #expect(state.lastError == nil)

        let successfulRelaunch = files.makeState()
        await successfulRelaunch.loadIfNeeded()
        #expect(clearedValues(in: successfulRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.bank.id) == [true])
        #expect(clearedValues(in: successfulRelaunch.ledger, transaction: fixture.transfer.id, account: fixture.savings.id) == [false])
    }

    private func makeTransferFixture() throws -> (
        ledger: Ledger,
        bank: Account,
        savings: Account,
        transfer: Transaction
    ) {
        let bank = Account(name: "Everyday", kind: .asset, currency: eur)
        let savings = Account(name: "Savings", kind: .asset, currency: eur)
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(savings)
        let date = Date(timeIntervalSince1970: 100)
        let transfer = Transaction(
            date: date,
            memo: "Move to savings",
            postings: [
                Posting(accountID: bank.id, money: Money(-40, currency: eur)),
                Posting(accountID: savings.id, money: Money(40, currency: eur))
            ],
            state: .finalized,
            createdAt: date,
            updatedAt: date,
            finalizedAt: date
        )
        try ledger.addTransaction(transfer)
        return (ledger, bank, savings, transfer)
    }

    private func clearedValues(
        in ledger: Ledger,
        transaction transactionID: TransactionID,
        account accountID: AccountID
    ) -> [Bool] {
        ledger.transactions
            .first { $0.id == transactionID }?
            .postings
            .filter { $0.accountID == accountID }
            .map(\.cleared) ?? []
    }
}

private struct ReconciliationFiles {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reconciliation-workflow-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var repository: LocalJSONAppDataRepository {
        LocalJSONAppDataRepository(directory: directory)
    }

    @MainActor
    func makeState(fault: ReconciliationSaveFault? = nil) -> AppState {
        let store = AppDataStore(directory: directory) { checkpoint in
            try fault?.check(checkpoint)
        }
        return AppState(dataRepository: LocalJSONAppDataRepository(store: store))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum ReconciliationTestError: Error {
    case writeFailed
}

private final class ReconciliationSaveFault: @unchecked Sendable {
    private let lock = NSLock()
    private var commitsToFail = 0

    func failNextCommit() {
        lock.lock()
        commitsToFail += 1
        lock.unlock()
    }

    func check(_ checkpoint: AppDataStore.Checkpoint) throws {
        guard checkpoint == .beforeCommit else { return }
        lock.lock()
        let shouldFail = commitsToFail > 0
        if shouldFail { commitsToFail -= 1 }
        lock.unlock()
        if shouldFail { throw ReconciliationTestError.writeFailed }
    }
}
