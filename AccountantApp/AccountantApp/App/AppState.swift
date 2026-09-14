import Foundation
import AccountantCore
#if canImport(Combine)
import Combine
#endif

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published private(set) var isLoading: Bool
    @Published private(set) var classificationRules: [ClassificationRuleConfiguration]
    @Published private(set) var budget: Budget

    /// Set when a store was found damaged. While this holds, every write is
    /// refused — see `DataProtection`.
    @Published private(set) var dataProtection: DataProtection = .ok

    @Published var lastError: AppError?

    private let dataRepository: any AppDataRepository
    private var didAttemptInitialLoad = false
    private var isReplacingData = false

    init(dataRepository: any AppDataRepository) {
        self.dataRepository = dataRepository
        self.ledger = Ledger()
        self.isLoading = false
        self.classificationRules = []
        self.budget = Budget()
        self.lastError = nil
    }

    func loadIfNeeded() async {
        guard !didAttemptInitialLoad, !isReplacingData else { return }

        didAttemptInitialLoad = true
        isLoading = true
        defer { isLoading = false }

        let loaded = await dataRepository.load()
        ledger = loaded.data.ledger
        budget = loaded.data.budget
        classificationRules = loaded.data.classificationRules
        dataProtection = loaded.damage.isEmpty ? .ok : .locked(loaded.damage)
        if loaded.damage.isEmpty { lastError = nil }
    }

    // MARK: - Data protection

    enum DataProtection: Equatable {
        case ok

        /// One or more stores were unreadable and have been quarantined. No write
        /// may proceed until the user resolves this.
        case locked([QuarantineRecord])

        var isLocked: Bool {
            if case .locked = self { return true }
            return false
        }

        var quarantined: [QuarantineRecord] {
            if case let .locked(records) = self { return records }
            return []
        }
    }

    var isDataLocked: Bool { dataProtection.isLocked }

    /// Resets all financial data. The recovery lock and originals survive any
    /// failed write; only a complete replacement dismisses recovery.
    @discardableResult
    func startFreshAfterDamage() async -> Bool {
        guard isDataLocked else { return false }
        return await replaceAllData(with: LedgerBackup(ledger: Ledger()))
    }

    /// Tries the load again — for when the cause was transient, such as the file
    /// being unavailable rather than corrupt.
    func retryLoadAfterDamage() async {
        guard isDataLocked, !isReplacingData, !isLoading else { return }
        didAttemptInitialLoad = false
        await loadIfNeeded()
    }

    private func refuseWriteWhileLocked() -> Bool {
        guard !isReplacingData, !isLoading else {
            lastError = AppError(message: "Please wait for your data to finish saving before making changes.")
            return true
        }
        guard isDataLocked else { return false }

        let names = dataProtection.quarantined
            .map { $0.quarantinedURL.lastPathComponent }
            .joined(separator: ", ")

        lastError = AppError(
            message: "Saving is paused because your saved data could not be read. The original file is safe as \(names). Choose Start fresh or Try again to continue."
        )

        return true
    }

    /// Whole-state replacements own the writer until they finish. The old
    /// visible state stays intact until the single snapshot commit succeeds.
    /// A failed destructive operation is never queued for automatic retry.
    private func replaceAllData(with backup: LedgerBackup) async -> Bool {
        guard !isReplacingData, !isLoading else { return false }
        isReplacingData = true
        defer { isReplacingData = false }

        flushTask?.cancel()
        flushTask = nil
        if let activeFlush { _ = await activeFlush.value }
        lastError = nil

        do {
            if isDataLocked {
                try await dataRepository.replaceForRecovery(backup)
                try await dataRepository.completeRecovery()
            } else {
                try await dataRepository.save(backup)
            }
        } catch {
            // An error can arrive after a commit (for example while completing
            // recovery). Re-read the authority to detect protection or a fully
            // committed replacement, without discarding unsaved old edits on a
            // pre-commit failure. Never allow a stale writer to resurrect them.
            let loaded = await dataRepository.load()
            if !loaded.damage.isEmpty {
                dataProtection = .locked(loaded.damage)
            } else if loaded.data.ledger == backup.ledger,
                      loaded.data.budget == backup.budget,
                      loaded.data.classificationRules == backup.classificationRules {
                acceptReplacement(backup)
            }
            lastError = AppError(error)
            return false
        }

        acceptReplacement(backup)
        lastError = nil
        return true
    }

    private func acceptReplacement(_ backup: LedgerBackup) {
        ledger = backup.ledger
        budget = backup.budget
        classificationRules = backup.classificationRules
        pending = PendingWrites()
        persistenceErrorID = nil
        dismissUndo()
        dataProtection = .ok
    }

    // MARK: - Persistence

    /// What has changed in memory but is not yet on disk.
    private struct PendingWrites {
        var ledger = false
        var budget = false
        var rules = false

        var isEmpty: Bool { !ledger && !budget && !rules }
    }

    private var pending = PendingWrites()
    private var flushTask: Task<Void, Never>?
    private var activeFlush: Task<Bool, Never>?
    private var persistenceErrorID: UUID?

    /// How long a change sits in memory before it is written.
    ///
    /// Absorbs bursts of changes. This interval is a real unsaved window; callers
    /// needing completion must await `flushPendingWrites()` and check its result.
    private static let flushDelay = Duration.milliseconds(400)

    /// Marks state dirty and schedules a coalesced write.
    private func scheduleFlush(_ mark: (inout PendingWrites) -> Void) {
        mark(&pending)

        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: AppState.flushDelay)
            guard !Task.isCancelled else { return }
            _ = await self?.flushPendingWrites()
        }
    }

    /// Writes everything that is dirty. Safe to call at any point.
    ///
    /// Call it directly when durability matters right now — a destructive action,
    /// or the app going to the background — rather than waiting out the debounce.
    @discardableResult
    func flushPendingWrites() async -> Bool {
        flushTask?.cancel()
        flushTask = nil

        guard !isDataLocked, !isReplacingData else { return false }

        // A concurrent caller joins the writer instead of returning before its
        // own dirty state has reached disk. The writer drains changes arriving
        // during a save, stopping on failure rather than spinning on a bad disk.
        if let activeFlush { return await activeFlush.value }
        guard !pending.isEmpty else { return true }

        let writer = Task { @MainActor in
            defer { self.activeFlush = nil }
            repeat {
                guard await self.writeDirtyStores() else { return false }
            } while !self.pending.isEmpty
            return true
        }
        activeFlush = writer
        return await writer.value
    }

    private func writeDirtyStores() async -> Bool {
        guard !isDataLocked else { return false }
        guard !pending.isEmpty else { return true }

        // Capture all components before suspension. Edits arriving during the
        // write set fresh pending flags and the shared writer drains them next.
        let snapshot = LedgerBackup(ledger: ledger, budget: budget,
                                    classificationRules: classificationRules)
        pending = PendingWrites()
        do {
            try await dataRepository.save(snapshot)
        } catch {
            // The unit of retry is the whole snapshot, including changes that
            // arrived while this save was suspended.
            pending = PendingWrites(ledger: true, budget: true, rules: true)
            let error = AppError(error)
            lastError = error
            persistenceErrorID = error.id
            return false
        }

        if lastError?.id == persistenceErrorID { lastError = nil }
        persistenceErrorID = nil
        return true
    }

    /// Applies a change in memory, then schedules the write.
    ///
    /// The order matters, and it is the reverse of what this used to do. Saving
    /// first and committing afterwards meant a suspension point sat between reading
    /// `ledger` and writing it back: two swipe actions fired in quick succession
    /// both read the same ledger, both saved their own copy, and the second silently
    /// discarded the first one's change. Committing synchronously on the main actor
    /// closes that window — there is no `await` between the read and the commit, so
    /// nothing can interleave.
    ///
    /// The trade is that a failed write now leaves the change visible on screen
    /// rather than rolling it back. That is the better failure: the change stays
    /// marked dirty and is retried, and the error is surfaced either way, whereas
    /// silently reverting an action the user just took only invites them to repeat
    /// it into the same failure.
    @discardableResult
    private func mutateAndSave(_ mutate: (inout Ledger) throws -> Void) async -> Bool {
        guard !refuseWriteWhileLocked() else { return false }

        var updated = ledger

        do {
            try mutate(&updated)
        } catch {
            lastError = AppError(error)
            return false
        }

        ledger = updated
        lastError = nil
        scheduleFlush { $0.ledger = true }
        return true
    }

    /// Creates an account.
    ///
    /// `currency` should be set for balance-bearing accounts and left nil for
    /// category accounts, which accept any currency. See `Account.currency`.
    @discardableResult
    func createAccount(
        name: String,
        kind: AccountKind,
        currency: Currency? = nil
    ) async -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedName.isEmpty else {
            lastError = AppError(message: "Account name cannot be empty.")
            return false
        }

        // Keep new accounts at the end of the user's ordering.
        let nextSortOrder = (ledger.accounts.values.map(\.sortOrder).max() ?? 0) + 1

        return await mutateAndSave { ledger in
            ledger.addAccount(
                Account(
                    name: cleanedName,
                    kind: kind,
                    currency: currency,
                    sortOrder: nextSortOrder
                )
            )
        }
    }

    @discardableResult
    func renameAccount(id: AccountID, to newName: String) async -> Bool {
        let cleanedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedName.isEmpty else {
            lastError = AppError(message: "Account name cannot be empty.")
            return false
        }

        return await mutateAndSave { ledger in
            try ledger.renameAccount(id: id, to: cleanedName)
        }
    }

    @discardableResult
    func archiveAccount(id: AccountID) async -> Bool {
        await mutateAndSave { ledger in
            try ledger.archiveAccount(id: id)
        }
    }

    @discardableResult
    func restoreAccount(id: AccountID) async -> Bool {
        await mutateAndSave { ledger in
            try ledger.restoreAccount(id: id)
        }
    }

    @discardableResult
    func createDraftExpense(
        paidFrom: AccountID,
        category: AccountID,
        amount: Money,
        date: Date,
        memo: String?
    ) async -> Bool {
        await createExpense(
            paidFrom: paidFrom,
            category: category,
            amount: amount,
            date: date,
            memo: memo,
            finalize: false
        )
    }

    @discardableResult
    func createFinalizedExpense(
        paidFrom: AccountID,
        category: AccountID,
        amount: Money,
        date: Date,
        memo: String?
    ) async -> Bool {
        await createExpense(
            paidFrom: paidFrom,
            category: category,
            amount: amount,
            date: date,
            memo: memo,
            finalize: true
        )
    }

    @discardableResult
    func createDraftIncome(
        receivedIn: AccountID,
        source: AccountID,
        amount: Money,
        date: Date,
        memo: String?
    ) async -> Bool {
        await createIncome(
            receivedIn: receivedIn,
            source: source,
            amount: amount,
            date: date,
            memo: memo,
            finalize: false
        )
    }

    @discardableResult
    func createFinalizedIncome(
        receivedIn: AccountID,
        source: AccountID,
        amount: Money,
        date: Date,
        memo: String?
    ) async -> Bool {
        await createIncome(
            receivedIn: receivedIn,
            source: source,
            amount: amount,
            date: date,
            memo: memo,
            finalize: true
        )
    }

    @discardableResult
    func createDraftTransfer(
        from: AccountID,
        to: AccountID,
        amount: Money,
        date: Date,
        memo: String?
    ) async -> Bool {
        await createTransfer(
            from: from,
            to: to,
            amount: amount,
            date: date,
            memo: memo,
            finalize: false
        )
    }

    @discardableResult
    func createFinalizedTransfer(
        from: AccountID,
        to: AccountID,
        amount: Money,
        date: Date,
        memo: String?
    ) async -> Bool {
        await createTransfer(
            from: from,
            to: to,
            amount: amount,
            date: date,
            memo: memo,
            finalize: true
        )
    }

    @discardableResult
    func finalizeTransaction(id: TransactionID) async -> Bool {
        await mutateAndSave { ledger in
            try ledger.finalizeTransaction(id: id)
        }
    }

    @discardableResult
    func deleteDraftTransaction(id: TransactionID) async -> Bool {
        // Captured before the delete so it can be offered back.
        let doomed = ledger.transactions.first { $0.id == id }

        let deleted = await mutateAndSave { ledger in
            try ledger.deleteDraftTransaction(id: id)
        }

        if deleted, let doomed {
            offerUndo(for: doomed)
        }

        return deleted
    }

    // MARK: - Undo

    /// A draft that was just deleted, kept only long enough to offer it back.
    struct DeletedDraft: Identifiable, Equatable {
        let transaction: AccountantCore.Transaction
        var id: TransactionID { transaction.id }
    }

    /// Deleting a draft is the one destructive action reachable from a single
    /// swipe with no confirmation.
    ///
    /// A confirmation dialog on every swipe would wreck the review flow, which is
    /// the one part of the app that has to be fast — you are going through a day's
    /// captures, and a modal between each one turns two minutes into ten. Holding
    /// the deleted entry for a few seconds covers the same mistake and costs the
    /// careful user nothing.
    @Published private(set) var recentlyDeletedDraft: DeletedDraft?

    private var undoExpiryTask: Task<Void, Never>?

    /// Long enough to notice the row vanish and react; short enough that the bar
    /// is gone before it becomes furniture.
    private static let undoWindow = Duration.seconds(6)

    private func offerUndo(for transaction: AccountantCore.Transaction) {
        recentlyDeletedDraft = DeletedDraft(transaction: transaction)

        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: AppState.undoWindow)
            guard !Task.isCancelled else { return }
            self?.recentlyDeletedDraft = nil
        }
    }

    /// Puts the deleted draft back.
    ///
    /// This can legitimately fail: if one of the accounts the entry referenced was
    /// archived in the meantime, the ledger refuses it. That is the guard working,
    /// and it surfaces as an error rather than a silent no-op.
    @discardableResult
    func undoDraftDeletion() async -> Bool {
        guard let pending = recentlyDeletedDraft else { return false }

        dismissUndo()

        return await mutateAndSave { ledger in
            try ledger.addTransaction(pending.transaction)
        }
    }

    func dismissUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        recentlyDeletedDraft = nil
    }

    /// Entries captured but not yet reviewed, oldest first.
    var draftTransactions: [AccountantCore.Transaction] {
        ledger.draftTransactions()
    }

    /// How many entries are waiting, without building the sorted list to find out.
    ///
    /// `draftTransactions()` sorts every transaction in the ledger before filtering.
    /// Several screens only ever wanted the count for a badge or a row label, and
    /// were paying for the sort to get it.
    var draftCount: Int {
        ledger.transactions.reduce(into: 0) { total, transaction in
            if transaction.state == .draft { total += 1 }
        }
    }

    /// Confirms a reviewed batch. All or nothing — see `Ledger.finalizeTransactions`.
    @discardableResult
    func confirmTransactions(ids: [TransactionID]) async -> Bool {
        guard !ids.isEmpty else { return true }

        return await mutateAndSave { ledger in
            try ledger.finalizeTransactions(ids: ids)
        }
    }

    /// Changes the purchase or income category while preserving separate fees.
    @discardableResult
    func recategorizeDraft(id: TransactionID, to categoryID: AccountID) async -> Bool {
        guard !refuseWriteWhileLocked() else { return false }
        guard let category = ledger.accounts[categoryID], category.status == .active,
              category.kind == .expense || category.kind == .income else {
            lastError = AppError(message: "Choose an active expense or income category.")
            return false
        }
        guard let transaction = ledger.transactions.first(where: { $0.id == id }) else {
            lastError = AppError(LedgerError.transactionNotFound(id))
            return false
        }
        let details = DraftReviewDetails(transaction: transaction, accounts: ledger.accounts)
        guard let index = details.categoryPostingIndex else {
            lastError = AppError(message: details.cannotRecategorizeReason ?? "This entry has no editable category.")
            return false
        }

        return await mutateAndSave { ledger in
            try ledger.updateDraftTransaction(id: id) { transaction in
                let posting = transaction.postings[index]
                transaction.postings[index] = Posting(
                    accountID: categoryID,
                    money: posting.money,
                    cleared: posting.cleared,
                    role: posting.role
                )
            }
        }
    }

    /// Records whether the bank has confirmed a transaction against one account.
    ///
    /// Works on finalized transactions by design — clearing is a statement fact,
    /// not an edit to the accounting.
    @discardableResult
    func setCleared(
        _ cleared: Bool,
        forAccount accountID: AccountID,
        in transactionID: TransactionID
    ) async -> Bool {
        await mutateAndSave { ledger in
            try ledger.setCleared(cleared, forAccount: accountID, in: transactionID)
        }
    }

    // MARK: - Destructive resets

    /// Clears every transaction, keeping accounts, categories and budgets.
    ///
    /// The one for throwing away test data without rebuilding your setup.
    @discardableResult
    func clearAllTransactions() async -> Bool {
        await mutateAndSave { ledger in
            ledger.removeAllTransactions()
        }
    }

    /// Removes accounts nothing has ever referenced, and any budget limits that
    /// were set on them.
    ///
    /// Accounts with history are kept: deleting them would strand postings
    /// pointing at nothing.
    ///
    /// The budget half matters because the accounts this removes — created, never
    /// used — are exactly the ones likely to carry a limit and no transactions. An
    /// earlier version dropped the account and left its `BudgetTarget` behind,
    /// pointing at an ID that no longer existed.
    @discardableResult
    func removeUnusedAccounts() async -> Bool {
        guard !refuseWriteWhileLocked() else { return false }

        var updatedLedger = ledger
        let removed = updatedLedger.removeUnusedAccounts()

        guard !removed.isEmpty else {
            lastError = nil
            return true
        }

        var updatedBudget = budget
        for account in removed {
            updatedBudget.forget(accountID: account.id)
        }

        ledger = updatedLedger
        budget = updatedBudget
        lastError = nil

        // Both changes are included in the same atomic snapshot.
        scheduleFlush {
            $0.ledger = true
            $0.budget = true
        }
        return await flushPendingWrites()
    }

    /// Replaces everything with the contents of a backup.
    ///
    /// Deliberately permitted while the data-protection lock is on. A damaged
    /// store is one of the main reasons anyone restores, and refusing would leave
    /// the user holding a good backup and no way to use it. The quarantined
    /// originals stay on disk either way.
    ///
    /// Flushed rather than debounced: someone restoring has just been told their
    /// current data is about to be replaced, and the write should have happened by
    /// the time they are looking at the result.
    @discardableResult
    func restore(from backup: LedgerBackup) async -> Bool {
        guard !isReplacingData, !isLoading else { return false }
        do {
            try backup.validateForRestore()
        } catch {
            lastError = AppError(error)
            return false
        }

        return await replaceAllData(with: backup)
    }

    /// Erases ledger, budget and import rules in one awaited snapshot commit.
    /// An interrupted replacement leaves a complete old/new state or recovery
    /// protection; it cannot publish only part of the erase.
    @discardableResult
    func eraseAllData() async -> Bool {
        await replaceAllData(with: LedgerBackup(ledger: Ledger()))
    }

    /// Clears every monthly limit, leaving the ledger alone.
    @discardableResult
    func clearBudget() async -> Bool {
        await saveBudget(Budget())
    }

    // MARK: - Budget

    /// Sets a monthly limit for a category, effective from `period` onward.
    @discardableResult
    func setBudgetTarget(
        amount: Money,
        for categoryID: AccountID,
        from period: BudgetPeriod
    ) async -> Bool {
        var updated = budget

        do {
            try updated.setTarget(
                amount: amount,
                for: categoryID,
                from: period,
                in: ledger
            )
        } catch {
            lastError = AppError(error)
            return false
        }

        return await saveBudget(updated)
    }

    /// Stops budgeting a category from `period` onward, leaving history intact.
    @discardableResult
    func removeBudgetTarget(
        for categoryID: AccountID,
        from period: BudgetPeriod
    ) async -> Bool {
        var updated = budget
        updated.removeTarget(for: categoryID, from: period)

        return await saveBudget(updated)
    }

    func budgetReport(
        for period: BudgetPeriod,
        currency: Currency? = nil
    ) -> BudgetReport {
        ledger.budgetReport(
            budget: budget,
            period: period,
            currency: currency ?? displayCurrency
        )
    }

    @discardableResult
    private func saveBudget(_ updated: Budget) async -> Bool {
        guard !refuseWriteWhileLocked() else { return false }

        budget = updated
        lastError = nil
        scheduleFlush { $0.budget = true }
        return true
    }

    /// Currency used where no account dictates one — dashboard roll-ups, mainly.
    ///
    /// Interim home for what should become a real setting. It at least replaces
    /// three separate `Currency("EUR")` literals scattered across views with one
    /// value that the whole app agrees on.
    var displayCurrency: Currency {
        Currency("EUR")
    }

    /// The currency to present an account in: its own if it declares one,
    /// otherwise the app default.
    func currency(for account: Account) -> Currency {
        account.currency ?? displayCurrency
    }

    @discardableResult
    func applyImportPreview(_ preview: ImportPreview, using pipeline: ImportPipeline) async -> ImportApplyReport? {
        // Writes directly rather than through mutateAndSave, so it needs the same
        // guard: importing into a ledger that failed to load would write an empty
        // one plus the import over the real file.
        guard !refuseWriteWhileLocked() else { return nil }

        var updated = ledger

        let report: ImportApplyReport

        do {
            report = try pipeline.applyImportPreview(preview, to: &updated)
        } catch {
            lastError = AppError(error)
            return nil
        }

        ledger = updated
        lastError = nil

        // Flushed rather than debounced: an import is a lot of work to lose, and
        // the user is already waiting on the result.
        scheduleFlush { $0.ledger = true }
        return await flushPendingWrites() ? report : nil
    }

    @discardableResult
    func createDescriptionContainsRule(
        needle: String,
        counterpartyAccountID: AccountID?,
        cleanedMemo: String?,
        id: UUID = UUID(),
        isEnabled: Bool = true
    ) async -> Bool {
        let rule = ClassificationRuleConfiguration(
            id: id,
            needle: needle,
            counterpartyAccountID: counterpartyAccountID,
            cleanedMemo: cleanedMemo,
            isEnabled: isEnabled
        )
        guard validateClassificationRule(rule) else { return false }
        var updatedRules = classificationRules
        // A failed write leaves the rule visible and dirty. Retrying the same
        // form must retry that rule, rather than append a duplicate.
        if let index = updatedRules.firstIndex(where: { $0.id == id }) {
            updatedRules[index] = rule
        } else {
            updatedRules.append(rule)
        }
        return await saveClassificationRules(updatedRules)
    }

    @discardableResult
    func updateClassificationRule(_ rule: ClassificationRuleConfiguration) async -> Bool {
        guard validateClassificationRule(rule) else { return false }
        guard let index = classificationRules.firstIndex(where: { $0.id == rule.id }) else {
            lastError = AppError(message: "This rule no longer exists.")
            return false
        }
        var rules = classificationRules
        rules[index] = rule
        return await saveClassificationRules(rules)
    }

    @discardableResult
    func setClassificationRuleEnabled(id: UUID, isEnabled: Bool) async -> Bool {
        guard var rule = classificationRules.first(where: { $0.id == id }) else {
            lastError = AppError(message: "This rule no longer exists.")
            return false
        }
        rule.isEnabled = isEnabled
        return await updateClassificationRule(rule)
    }

    @discardableResult
    func moveClassificationRules(fromOffsets offsets: IndexSet, toOffset destination: Int) async -> Bool {
        guard (0...classificationRules.count).contains(destination),
              offsets.allSatisfy({ classificationRules.indices.contains($0) }) else {
            lastError = AppError(message: "The rule order changed. Try moving the rule again.")
            return false
        }
        var rules = classificationRules
        let moved = offsets.sorted().map { rules[$0] }
        for index in offsets.sorted().reversed() { rules.remove(at: index) }
        let insertion = destination - offsets.filter { $0 < destination }.count
        rules.insert(contentsOf: moved, at: insertion)
        return await saveClassificationRules(rules)
    }

    @discardableResult
    func deleteClassificationRule(id: UUID) async -> Bool {
        let updatedRules = classificationRules.filter { $0.id != id }
        guard updatedRules.count != classificationRules.count else {
            return await flushPendingWrites()
        }
        return await saveClassificationRules(updatedRules)
    }

    var applicableClassificationRuleCount: Int {
        applicableClassificationRules.count
    }

    func transactionClassifier() -> TransactionClassifier {
        ClassificationRuleConfiguration.makeClassifier(from: applicableClassificationRules)
    }

    var applicableClassificationRules: [ClassificationRuleConfiguration] {
        classificationRules.filter { classificationRuleUnavailableReason($0) == nil }
    }

    func classificationRuleTest(sampleDescription: String) -> ClassificationRuleEvaluation {
        applicableClassificationRules.evaluate(description: sampleDescription)
    }

    func classificationRuleUnavailableReason(_ rule: ClassificationRuleConfiguration) -> String? {
        if !rule.isEnabled { return "Paused" }
        if rule.needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Match text is empty" }
        if rule.makeRule() == nil { return "This rule makes no changes" }
        if let id = rule.counterpartyAccountID {
            guard let account = ledger.accounts[id] else { return "Category no longer exists" }
            guard account.status == .active else { return "Category is archived" }
            guard account.kind == .expense || account.kind == .income else {
                return "Choose an expense or income category"
            }
        }
        return nil
    }

    private func validateClassificationRule(_ rule: ClassificationRuleConfiguration) -> Bool {
        guard !refuseWriteWhileLocked() else { return false }
        guard !rule.needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = AppError(message: "Rule match text cannot be empty.")
            return false
        }
        guard rule.counterpartyAccountID != nil || Self.cleanedOptionalText(rule.cleanedMemo) != nil else {
            lastError = AppError(message: "Rule must change an account, memo, or both.")
            return false
        }
        if rule.isEnabled, let reason = classificationRuleUnavailableReason(rule) {
            lastError = AppError(message: reason)
            return false
        }
        return true
    }

    @discardableResult
    private func saveClassificationRules(_ updatedRules: [ClassificationRuleConfiguration]) async -> Bool {
        guard !refuseWriteWhileLocked() else { return false }

        classificationRules = updatedRules
        lastError = nil
        scheduleFlush { $0.rules = true }
        return await flushPendingWrites()
    }

    private func createExpense(
        paidFrom: AccountID,
        category: AccountID,
        amount: Money,
        date: Date,
        memo: String?,
        finalize: Bool
    ) async -> Bool {
        await createTransaction(finalize: finalize) {
            try Transaction.draftExpense(
                paidFrom: paidFrom,
                category: category,
                amount: amount,
                date: date,
                memo: cleanedMemo(memo)
            )
        }
    }

    private func createIncome(
        receivedIn: AccountID,
        source: AccountID,
        amount: Money,
        date: Date,
        memo: String?,
        finalize: Bool
    ) async -> Bool {
        await createTransaction(finalize: finalize) {
            try Transaction.draftIncome(
                receivedIn: receivedIn,
                source: source,
                amount: amount,
                date: date,
                memo: cleanedMemo(memo)
            )
        }
    }

    private func createTransfer(
        from: AccountID,
        to: AccountID,
        amount: Money,
        date: Date,
        memo: String?,
        finalize: Bool
    ) async -> Bool {
        await createTransaction(finalize: finalize) {
            try Transaction.draftTransfer(
                from: from,
                to: to,
                amount: amount,
                date: date,
                memo: cleanedMemo(memo)
            )
        }
    }

    @discardableResult
    private func createTransaction(
        finalize: Bool,
        build: () throws -> Transaction
    ) async -> Bool {
        await mutateAndSave { ledger in
            let transaction = try build()
            try ledger.addTransaction(transaction)

            if finalize {
                try ledger.finalizeTransaction(id: transaction.id)
            }
        }
    }

    private func cleanedMemo(_ memo: String?) -> String? {
        Self.cleanedOptionalText(memo)
    }

    private static func cleanedOptionalText(_ text: String?) -> String? {
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }
}
