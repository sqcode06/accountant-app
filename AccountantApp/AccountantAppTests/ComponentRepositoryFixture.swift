import AccountantCore
@testable import AccountantApp

/// Test-only bridge for unit fixtures that still model the three legacy stores
/// separately. Product code must use an `AppDataRepository` directly.
private actor ComponentRepositoryFixtureAdapter: AppDataRepository {
    private let ledgerRepository: any LedgerRepository
    private let classificationRuleRepository: any ClassificationRuleRepository
    private let budgetRepository: any BudgetRepository

    init(
        ledgerRepository: any LedgerRepository,
        classificationRuleRepository: any ClassificationRuleRepository,
        budgetRepository: any BudgetRepository
    ) {
        self.ledgerRepository = ledgerRepository
        self.classificationRuleRepository = classificationRuleRepository
        self.budgetRepository = budgetRepository
    }

    func load() async -> AppDataLoadResult {
        let ledgerOutcome = await ledgerRepository.load()
        let ruleOutcome = await classificationRuleRepository.load()
        let budgetOutcome = await budgetRepository.load()

        var damage: [QuarantineRecord] = []

        let ledger: Ledger
        switch ledgerOutcome {
        case let .loaded(value): ledger = value
        case .empty: ledger = Ledger()
        case let .unreadable(record):
            ledger = Ledger()
            damage.append(record)
        }

        let classificationRules: [ClassificationRuleConfiguration]
        switch ruleOutcome {
        case let .loaded(value): classificationRules = value
        case .empty: classificationRules = []
        case let .unreadable(record):
            classificationRules = []
            damage.append(record)
        }

        let budget: Budget
        switch budgetOutcome {
        case let .loaded(value): budget = value
        case .empty: budget = Budget()
        case let .unreadable(record):
            budget = Budget()
            damage.append(record)
        }

        return AppDataLoadResult(
            data: LedgerBackup(
                ledger: ledger,
                budget: budget,
                classificationRules: classificationRules
            ),
            damage: damage
        )
    }

    func save(_ data: LedgerBackup) async throws {
        try await ledgerRepository.save(data.ledger)
        try await budgetRepository.save(data.budget)
        try await classificationRuleRepository.save(data.classificationRules)
    }

    func replaceForRecovery(_ data: LedgerBackup) async throws {
        try await ledgerRepository.replaceForRecovery(data.ledger)
        try await budgetRepository.replaceForRecovery(data.budget)
        try await classificationRuleRepository.replaceForRecovery(data.classificationRules)
    }

    func completeRecovery() async throws {
        try await ledgerRepository.completeRecovery()
        try await budgetRepository.completeRecovery()
        try await classificationRuleRepository.completeRecovery()
    }
}

extension AppState {
    /// Preserves existing component mocks while unit tests move to a snapshot
    /// repository. This initializer is test-only and unavailable to the app.
    convenience init(
        repository: any LedgerRepository,
        classificationRuleRepository: any ClassificationRuleRepository = EmptyClassificationRuleRepository(),
        budgetRepository: any BudgetRepository = EmptyBudgetRepository()
    ) {
        self.init(
            dataRepository: ComponentRepositoryFixtureAdapter(
                ledgerRepository: repository,
                classificationRuleRepository: classificationRuleRepository,
                budgetRepository: budgetRepository
            )
        )
    }
}
