import Foundation
import AccountantCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published private(set) var isLoading: Bool
    @Published private(set) var classificationRules: [ClassificationRuleConfiguration]
    @Published private(set) var budget: Budget
    @Published var lastError: AppError?

    private let repository: LedgerRepository
    private let classificationRuleRepository: ClassificationRuleRepository
    private let budgetRepository: BudgetRepository
    private var didAttemptInitialLoad = false

    init(
        repository: LedgerRepository,
        classificationRuleRepository: ClassificationRuleRepository = EmptyClassificationRuleRepository(),
        budgetRepository: BudgetRepository = EmptyBudgetRepository()
    ) {
        self.repository = repository
        self.classificationRuleRepository = classificationRuleRepository
        self.budgetRepository = budgetRepository
        self.ledger = Ledger()
        self.isLoading = false
        self.classificationRules = []
        self.budget = Budget()
        self.lastError = nil
    }

    func loadIfNeeded() async {
        guard !didAttemptInitialLoad else { return }

        didAttemptInitialLoad = true
        isLoading = true
        defer { isLoading = false }

        var loadingError: Error?

        do {
            ledger = try await repository.loadOrCreate()
        } catch {
            ledger = Ledger()
            loadingError = error
        }

        do {
            classificationRules = try await classificationRuleRepository.loadOrCreate()
        } catch {
            classificationRules = []

            if loadingError == nil {
                loadingError = error
            }
        }

        do {
            budget = try await budgetRepository.loadOrCreate()
        } catch {
            budget = Budget()

            if loadingError == nil {
                loadingError = error
            }
        }

        if let loadingError {
            lastError = AppError(loadingError)
        } else {
            lastError = nil
        }
    }

    @discardableResult
    func save() async -> Bool {
        do {
            try await repository.save(ledger)
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
    }

    @discardableResult
    private func mutateAndSave(_ mutate: (inout Ledger) throws -> Void) async -> Bool {
        var updated = ledger

        do {
            try mutate(&updated)
            try await repository.save(updated)
            ledger = updated
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
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
        await mutateAndSave { ledger in
            try ledger.deleteDraftTransaction(id: id)
        }
    }

    /// Entries captured but not yet reviewed, oldest first.
    var draftTransactions: [AccountantCore.Transaction] {
        ledger.draftTransactions()
    }

    /// Confirms a reviewed batch. All or nothing — see `Ledger.finalizeTransactions`.
    @discardableResult
    func confirmTransactions(ids: [TransactionID]) async -> Bool {
        guard !ids.isEmpty else { return true }

        return await mutateAndSave { ledger in
            try ledger.finalizeTransactions(ids: ids)
        }
    }

    /// Moves a draft to a different category — the fix review exists for.
    ///
    /// The expense account IDs are read *before* the mutation closure runs.
    /// Reading `ledger` inside a closure that is mutating it would be an
    /// exclusivity violation.
    @discardableResult
    func recategorizeDraft(id: TransactionID, to categoryID: AccountID) async -> Bool {
        let expenseAccountIDs = Set(
            ledger.accounts.values
                .filter { $0.kind == .expense }
                .map(\.id)
        )

        return await mutateAndSave { ledger in
            try ledger.updateDraftTransaction(id: id) { transaction in
                transaction.postings = transaction.postings.map { posting in
                    guard expenseAccountIDs.contains(posting.accountID) else {
                        return posting
                    }

                    return Posting(
                        accountID: categoryID,
                        money: posting.money,
                        cleared: posting.cleared
                    )
                }
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

    /// Removes accounts nothing has ever referenced.
    ///
    /// Accounts with history are kept: deleting them would strand postings
    /// pointing at nothing.
    @discardableResult
    func removeUnusedAccounts() async -> Bool {
        await mutateAndSave { ledger in
            ledger.removeUnusedAccounts()
        }
    }

    /// Erases everything — ledger, budget and import rules.
    ///
    /// Each store is written separately, so a mid-way failure can leave the app
    /// partly erased. That is reported rather than hidden: the alternative is
    /// pretending a wipe succeeded when the budget file is still on disk.
    @discardableResult
    func eraseAllData() async -> Bool {
        var succeeded = true

        do {
            try await repository.save(Ledger())
            ledger = Ledger()
        } catch {
            lastError = AppError(error)
            succeeded = false
        }

        do {
            try await budgetRepository.save(Budget())
            budget = Budget()
        } catch {
            if succeeded { lastError = AppError(error) }
            succeeded = false
        }

        do {
            try await classificationRuleRepository.save([])
            classificationRules = []
        } catch {
            if succeeded { lastError = AppError(error) }
            succeeded = false
        }

        if succeeded { lastError = nil }

        return succeeded
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
        do {
            try await budgetRepository.save(updated)
            budget = updated
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
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
        var updated = ledger

        do {
            let report = try pipeline.applyImportPreview(preview, to: &updated)
            try await repository.save(updated)
            ledger = updated
            lastError = nil
            return report
        } catch {
            lastError = AppError(error)
            return nil
        }
    }

    @discardableResult
    func createDescriptionContainsRule(
        needle: String,
        counterpartyAccountID: AccountID?,
        cleanedMemo: String?
    ) async -> Bool {
        let cleanedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMemo = Self.cleanedOptionalText(cleanedMemo)

        guard !cleanedNeedle.isEmpty else {
            lastError = AppError(message: "Rule match text cannot be empty.")
            return false
        }

        guard counterpartyAccountID != nil || normalizedMemo != nil else {
            lastError = AppError(message: "Rule must change an account, memo, or both.")
            return false
        }

        let rule = ClassificationRuleConfiguration(
            needle: cleanedNeedle,
            counterpartyAccountID: counterpartyAccountID,
            cleanedMemo: normalizedMemo
        )

        var updatedRules = classificationRules
        updatedRules.append(rule)
        return await saveClassificationRules(updatedRules)
    }

    @discardableResult
    func deleteClassificationRule(id: UUID) async -> Bool {
        let updatedRules = classificationRules.filter { $0.id != id }
        guard updatedRules.count != classificationRules.count else {
            lastError = nil
            return true
        }
        return await saveClassificationRules(updatedRules)
    }

    var applicableClassificationRuleCount: Int {
        applicableClassificationRules.count
    }

    func transactionClassifier() -> TransactionClassifier {
        ClassificationRuleConfiguration.makeClassifier(from: applicableClassificationRules)
    }

    private var applicableClassificationRules: [ClassificationRuleConfiguration] {
        classificationRules.filter { rule in
            guard rule.makeRule() != nil else {
                return false
            }

            guard let accountID = rule.counterpartyAccountID else {
                return true
            }

            return ledger.accounts[accountID]?.status == .active
        }
    }

    @discardableResult
    private func saveClassificationRules(_ updatedRules: [ClassificationRuleConfiguration]) async -> Bool {
        do {
            try await classificationRuleRepository.save(updatedRules)
            classificationRules = updatedRules
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
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
