import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

/// The app layer around classification rules: loading them into AppState,
/// creating them, and persisting them.
///
/// The rule type itself moved into the core, and its behaviour is tested there.
/// What is left here is the part that genuinely belongs to the app — AppState and
/// the on-disk repository.
struct ClassificationRuleStorageTests {

    @MainActor
    @Test func appStateLoadsClassificationRules() async throws {
        let fixture = ClassificationFixture()
        let storedRule = ClassificationRuleConfiguration(
            needle: "rimi",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Rimi"
        )
        let ledgerRepository = TestLedgerRepository(ledger: fixture.ledger)
        let ruleRepository = TestClassificationRuleRepository(rules: [storedRule])
        let appState = AppState(
            repository: ledgerRepository,
            classificationRuleRepository: ruleRepository
        )

        await appState.loadIfNeeded()

        #expect(appState.classificationRules == [storedRule])
        #expect(appState.lastError == nil)
    }

    @MainActor
    @Test func appStateSavesNewDescriptionContainsRule() async throws {
        let fixture = ClassificationFixture()
        let ledgerRepository = TestLedgerRepository(ledger: fixture.ledger)
        let ruleRepository = TestClassificationRuleRepository()
        let appState = AppState(
            repository: ledgerRepository,
            classificationRuleRepository: ruleRepository
        )

        let success = await appState.createDescriptionContainsRule(
            needle: "  RIMI  ",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "  Rimi  "
        )

        #expect(success)
        #expect(appState.classificationRules.count == 1)
        #expect(appState.classificationRules.first?.needle == "RIMI")
        #expect(appState.classificationRules.first?.cleanedMemo == "Rimi")
        #expect(await ruleRepository.savedRules.count == 1)
        #expect(appState.lastError == nil)
    }

    @MainActor
    @Test func appStateRejectsRulesWithNoEffect() async throws {
        let repository = TestLedgerRepository()
        let ruleRepository = TestClassificationRuleRepository()
        let appState = AppState(
            repository: repository,
            classificationRuleRepository: ruleRepository
        )

        let success = await appState.createDescriptionContainsRule(
            needle: "RIMI",
            counterpartyAccountID: nil,
            cleanedMemo: "   "
        )

        #expect(!success)
        #expect(appState.classificationRules.isEmpty)
        #expect(await ruleRepository.savedRules.isEmpty)
        #expect(appState.lastError?.message == "Rule must change an account, memo, or both.")
    }

    @Test func localJSONClassificationRuleRepositoryRoundTripsRules() async throws {
        let fixture = ClassificationFixture()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("classification-rules-\(UUID().uuidString).json")
        let repository = LocalJSONClassificationRuleRepository(fileURL: fileURL)
        let rule = ClassificationRuleConfiguration(
            needle: "bolt food",
            counterpartyAccountID: fixture.food.id,
            cleanedMemo: "Bolt Food"
        )

        try await repository.save([rule])
        let loaded = try await repository.loadOrCreate()

        #expect(loaded == [rule])

        try? FileManager.default.removeItem(at: fileURL)
    }
}

private actor TestLedgerRepository: LedgerRepository {
    private var storedLedger: Ledger

    init(ledger: Ledger = Ledger()) {
        self.storedLedger = ledger
    }

    func loadOrCreate() async throws -> Ledger {
        storedLedger
    }

    func save(_ ledger: Ledger) async throws {
        storedLedger = ledger
    }
}

private actor TestClassificationRuleRepository: ClassificationRuleRepository {
    private var storedRules: [ClassificationRuleConfiguration]
    private(set) var savedRules: [[ClassificationRuleConfiguration]] = []

    init(rules: [ClassificationRuleConfiguration] = []) {
        self.storedRules = rules
    }

    func loadOrCreate() async throws -> [ClassificationRuleConfiguration] {
        storedRules
    }

    func save(_ rules: [ClassificationRuleConfiguration]) async throws {
        storedRules = rules
        savedRules.append(rules)
    }
}

private struct ClassificationFixture {
    let eur = Currency("EUR")
    let now = Date(timeIntervalSince1970: 123_456)
    let bank = Account(name: "LHV", kind: .asset)
    let uncategorized = Account(name: "Uncategorized", kind: .clearing)
    let groceries = Account(name: "Groceries", kind: .expense)
    let food = Account(name: "Food Delivery", kind: .expense)

    var ledger: Ledger {
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)
        ledger.addAccount(groceries)
        ledger.addAccount(food)
        return ledger
    }

    var pipeline: ImportPipeline {
        ImportPipeline(
            source: "LHV",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )
    }

    func line(description: String) -> BankLine {
        BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-12),
            currency: eur,
            description: description,
            externalID: "CARD-1"
        )
    }
}
