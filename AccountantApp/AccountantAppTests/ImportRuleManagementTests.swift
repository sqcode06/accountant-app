import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

/// AppState behaviour behind the Import Rules manager. These tests focus on the
/// saved-order and retry guarantees that a settings screen cannot prove itself.
struct ImportRuleManagementTests {

    @MainActor
    @Test func createRetryWithRetainedIDDoesNotDuplicateAfterSaveFailure() async throws {
        let fixture = RuleManagementFixture()
        let repository = RuleManagementRepository(failSaveCount: 1)
        let state = makeState(fixture: fixture, rules: repository)
        await state.loadIfNeeded()

        let id = UUID()
        let firstAttempt = await state.createDescriptionContainsRule(
            needle: "Rimi",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Groceries",
            id: id
        )

        #expect(!firstAttempt)
        #expect(state.classificationRules.map(\.id) == [id])
        #expect(state.lastError?.message.isEmpty == false)

        let retry = await state.createDescriptionContainsRule(
            needle: "Rimi",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Groceries",
            id: id
        )

        #expect(retry)
        #expect(state.classificationRules.map(\.id) == [id])
        #expect(await repository.storedRules.map(\.id) == [id])
    }

    @MainActor
    @Test func editingRulePreservesIdentityOrderAndChangedFields() async throws {
        let fixture = RuleManagementFixture()
        let first = fixture.rule(needle: "rimi", category: fixture.groceries, memo: "Rimi")
        let second = fixture.rule(needle: "bolt", category: fixture.transport, memo: "Bolt")
        let repository = RuleManagementRepository(rules: [first, second])
        let state = makeState(fixture: fixture, rules: repository)
        await state.loadIfNeeded()

        let edited = ClassificationRuleConfiguration(
            id: first.id,
            name: first.name,
            needle: "Rimi Eesti",
            counterpartyAccountID: fixture.transport.id,
            cleanedMemo: "Weekly groceries"
        )

        let saved = await state.updateClassificationRule(edited)

        #expect(saved)
        #expect(state.classificationRules.map(\.id) == [first.id, second.id])
        #expect(state.classificationRules.first?.needle == "Rimi Eesti")
        #expect(state.classificationRules.first?.cleanedMemo == "Weekly groceries")
        #expect(state.classificationRules.first?.counterpartyAccountID == fixture.transport.id)
        #expect(await repository.storedRules == state.classificationRules)
    }

    @MainActor
    @Test func pausingRuleRemovesItFromEvaluationAndClassifierUntilResumed() async throws {
        let fixture = RuleManagementFixture()
        let rule = fixture.rule(needle: "rimi", category: fixture.groceries, memo: "Rimi")
        let repository = RuleManagementRepository(rules: [rule])
        let state = makeState(fixture: fixture, rules: repository)
        await state.loadIfNeeded()

        #expect(state.classificationRuleTest(sampleDescription: "RIMI EESTI").matches.map(\.id) == [rule.id])
        #expect(state.transactionClassifier().classify(
            line: fixture.line(description: "RIMI EESTI"),
            current: fixture.draftTransaction
        )?.counterpartyAccountID == fixture.groceries.id)

        #expect(await state.setClassificationRuleEnabled(id: rule.id, isEnabled: false))
        #expect(state.classificationRuleTest(sampleDescription: "RIMI EESTI").matches.isEmpty)
        #expect(state.transactionClassifier().classify(
            line: fixture.line(description: "RIMI EESTI"),
            current: fixture.draftTransaction
        ) == nil)

        #expect(await state.setClassificationRuleEnabled(id: rule.id, isEnabled: true))
        #expect(state.classificationRuleTest(sampleDescription: "RIMI EESTI").suggestion?.cleanedMemo == "Rimi")
    }

    @MainActor
    @Test func reorderingOverlappingRulesChangesWinnerAndSurvivesJSONReload() async throws {
        let fixture = RuleManagementFixture()
        let first = fixture.rule(needle: "shop", category: fixture.groceries, memo: "Groceries")
        let second = fixture.rule(needle: "shop", category: fixture.transport, memo: "Transport")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-management-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Seed the pre-snapshot layout so the first save must migrate all three
        // component files into the unified repository.
        try JSONLedgerStore(fileURL: directory.appendingPathComponent("ledger.json"))
            .save(fixture.ledger)
        try JSONFileStore<Budget>(
            fileURL: directory.appendingPathComponent("budget.json"),
            fallback: { Budget() }
        ).save(Budget())
        try JSONFileStore<[ClassificationRuleConfiguration]>(
            fileURL: directory.appendingPathComponent("classification-rules.json"),
            fallback: { [] }
        ).save([first, second])

        let dataRepository = LocalJSONAppDataRepository(directory: directory)
        let state = AppState(dataRepository: dataRepository)
        await state.loadIfNeeded()

        #expect(state.classificationRuleTest(sampleDescription: "shop today").suggestion?.counterpartyAccountID == fixture.transport.id)
        #expect(await state.moveClassificationRules(fromOffsets: IndexSet(integer: 0), toOffset: 2))
        #expect(state.classificationRuleTest(sampleDescription: "shop today").suggestion?.counterpartyAccountID == fixture.groceries.id)

        let reloaded = AppState(dataRepository: dataRepository)
        await reloaded.loadIfNeeded()

        #expect(reloaded.classificationRules.map(\.id) == [second.id, first.id])
        #expect(reloaded.classificationRuleTest(sampleDescription: "shop today").suggestion?.counterpartyAccountID == fixture.groceries.id)
    }

    @MainActor
    @Test func unavailableCategoriesAreExplainedOmittedAndRejectedForEnabledEdits() async throws {
        let fixture = RuleManagementFixture()
        let active = fixture.rule(needle: "valid", category: fixture.groceries, memo: "Valid")
        let archived = fixture.rule(needle: "archived", category: fixture.archivedExpense, memo: "Archived")
        let missing = ClassificationRuleConfiguration(
            needle: "missing",
            counterpartyAccountID: AccountID(),
            cleanedMemo: "Missing"
        )
        let repository = RuleManagementRepository(rules: [active, archived, missing])
        let state = makeState(fixture: fixture, rules: repository)
        await state.loadIfNeeded()

        #expect(state.classificationRuleUnavailableReason(archived)?.isEmpty == false)
        #expect(state.classificationRuleUnavailableReason(missing)?.isEmpty == false)
        #expect(state.classificationRuleTest(sampleDescription: "archived missing valid").matches.map(\.id) == [active.id])

        let nonCategoryEdit = ClassificationRuleConfiguration(
            id: active.id,
            name: active.name,
            needle: active.needle,
            counterpartyAccountID: fixture.bank.id,
            cleanedMemo: active.cleanedMemo,
            isEnabled: true
        )
        #expect(await state.updateClassificationRule(nonCategoryEdit) == false)
        #expect(state.lastError?.message.isEmpty == false)
        #expect(state.classificationRules.first == active)

        let archivedEdit = ClassificationRuleConfiguration(
            id: active.id,
            name: active.name,
            needle: active.needle,
            counterpartyAccountID: fixture.archivedExpense.id,
            cleanedMemo: active.cleanedMemo,
            isEnabled: true
        )
        #expect(await state.updateClassificationRule(archivedEdit) == false)
        #expect(state.classificationRules.first == active)
    }

    @MainActor
    @Test func deleteFailureKeepsRemovalDirtyUntilExplicitRetrySucceeds() async throws {
        let fixture = RuleManagementFixture()
        let rule = fixture.rule(needle: "rimi", category: fixture.groceries, memo: "Rimi")
        let repository = RuleManagementRepository(rules: [rule], failSaveCount: 1)
        let state = makeState(fixture: fixture, rules: repository)
        await state.loadIfNeeded()

        let deleted = await state.deleteClassificationRule(id: rule.id)

        #expect(!deleted)
        #expect(state.classificationRules.isEmpty)
        #expect(state.lastError?.message.isEmpty == false)
        #expect(await state.flushPendingWrites())
        #expect(await repository.storedRules.isEmpty)
    }

    @MainActor
    private func makeState(
        fixture: RuleManagementFixture,
        rules: any ClassificationRuleRepository
    ) -> AppState {
        AppState(
            repository: RuleManagementLedgerRepository(ledger: fixture.ledger),
            classificationRuleRepository: rules
        )
    }
}

private struct RuleManagementFixture {
    let currency = Currency("EUR")
    let bank = Account(name: "Bank", kind: .asset, currency: Currency("EUR"))
    let groceries = Account(name: "Groceries", kind: .expense)
    let transport = Account(name: "Transport", kind: .expense)
    let archivedExpense = Account(name: "Old category", kind: .expense)

    var ledger: Ledger {
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(groceries)
        ledger.addAccount(transport)
        ledger.addAccount(archivedExpense)
        try! ledger.archiveAccount(id: archivedExpense.id)
        return ledger
    }

    var draftTransaction: Transaction {
        Transaction.draft(postings: [
            Posting(accountID: bank.id, money: Money(-1, currency: currency)),
            Posting(accountID: groceries.id, money: Money(1, currency: currency))
        ])
    }

    func rule(
        needle: String,
        category: Account,
        memo: String
    ) -> ClassificationRuleConfiguration {
        ClassificationRuleConfiguration(
            needle: needle,
            counterpartyAccountID: category.id,
            cleanedMemo: memo
        )
    }

    func line(description: String) -> BankLine {
        BankLine(
            date: Date(timeIntervalSince1970: 123),
            amount: -1,
            currency: currency,
            description: description,
            externalID: "rule-test"
        )
    }
}

private actor RuleManagementLedgerRepository: LedgerRepository {
    private var ledger: Ledger

    init(ledger: Ledger) {
        self.ledger = ledger
    }

    func loadOrCreate() async throws -> Ledger { ledger }

    func save(_ ledger: Ledger) async throws {
        self.ledger = ledger
    }
}

private enum RuleManagementRepositoryError: Error {
    case saveFailed
}

private actor RuleManagementRepository: ClassificationRuleRepository {
    private(set) var storedRules: [ClassificationRuleConfiguration]
    private var remainingSaveFailures: Int

    init(rules: [ClassificationRuleConfiguration] = [], failSaveCount: Int = 0) {
        self.storedRules = rules
        self.remainingSaveFailures = failSaveCount
    }

    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] {
        storedRules
    }

    func save(_ rules: [ClassificationRuleConfiguration]) async throws {
        if remainingSaveFailures > 0 {
            remainingSaveFailures -= 1
            throw RuleManagementRepositoryError.saveFailed
        }

        storedRules = rules
    }
}
