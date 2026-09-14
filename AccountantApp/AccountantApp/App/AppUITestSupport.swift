#if DEBUG
import Foundation
import AccountantCore

/// A deterministic, persistent app sandbox for UI tests.
///
/// The opt-in flag and every seed/reset path are compiled out of Release builds.
/// Each test run supplies an identifier, which gives it separate JSON stores and
/// a separate UserDefaults suite. A relaunch with the same identifier reads the
/// state the previous process persisted.
struct AppUITestFixture {
    static let launchArgument = "--accountant-ui-testing"
    static let resetArgument = "--accountant-ui-testing-reset"
    static let runIDVariable = "ACCOUNTANT_UI_TEST_RUN_ID"
    static let nowVariable = "ACCOUNTANT_UI_TEST_NOW"
    static let ledgerSeedVariable = "ACCOUNTANT_UI_TEST_LEDGER_SEED"
    static let failFirstBudgetStopVariable = "ACCOUNTANT_UI_TEST_FAIL_FIRST_BUDGET_STOP"
    static let importRulesSeed = "import-rules"

    let dataRepository: any AppDataRepository
    let defaults: UserDefaults
    let clock: AppClock

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppUITestFixture? {
        guard arguments.contains(launchArgument) else { return nil }

        let rawRunID = environment[runIDVariable] ?? "local"
        let runID = sanitized(rawRunID)
        let fixtureDirectory = fixtureDirectory(runID: runID)

        let suiteName = "dev.sqcode.AccountantApp.UITests.\(runID)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create the isolated UI-test defaults suite")
        }

        do {
            if arguments.contains(resetArgument) {
                try removeFixtureDirectory(fixtureDirectory)
                defaults.removePersistentDomain(forName: suiteName)
            }

            try FileManager.default.createDirectory(
                at: fixtureDirectory,
                withIntermediateDirectories: true
            )

            let ledgerURL = fixtureDirectory.appendingPathComponent("ledger.json")
            let seededURL = fixtureDirectory.appendingPathComponent("fixture-seeded")
            let ledgerSeed = LedgerSeed(
                rawValue: environment[ledgerSeedVariable] ?? ""
            ) ?? .standard
            if !FileManager.default.fileExists(atPath: seededURL.path) {
                if !FileManager.default.fileExists(atPath: ledgerURL.path) {
                    try JSONLedgerStore(fileURL: ledgerURL).save(try makeLedger(seed: ledgerSeed))
                }
                try Data().write(to: seededURL, options: .atomic)
            }
            if ledgerSeed == .restoreErase {
                let backupURL = fixtureDirectory.appendingPathComponent("restore-backup.json")
                if !FileManager.default.fileExists(atPath: backupURL.path) {
                    try LedgerBackupCoder.encode(makeRestoreBackup()).write(to: backupURL, options: .atomic)
                }
            }

            let importStatementURL = fixtureDirectory
                .appendingPathComponent(importRulesStatementFileName)
            if ledgerSeed == .importRules,
               !FileManager.default.fileExists(atPath: importStatementURL.path) {
                try writeImportRulesStatement(to: fixtureDirectory)
            }

            // Avoid onboarding and the notification permission prompt. These are
            // tested separately from the accounting workflow.
            defaults.set("completed", forKey: "onboardingStatus")
            defaults.set(true, forKey: "reviewReminderDidAskPermission")
            defaults.set(false, forKey: "reviewReminderEnabled")

            let fixedDate = environment[nowVariable]
                .flatMap(ISO8601DateFormatter().date(from:))
                ?? Date(timeIntervalSince1970: 1_789_300_800) // 2026-09-13 12:00 UTC

            let repository = LocalJSONAppDataRepository(directory: fixtureDirectory)
            let dataRepository: any AppDataRepository = environment[failFirstBudgetStopVariable] == "1"
                ? FailFirstCurrentBudgetStopRepository(base: repository)
                : repository

            return AppUITestFixture(
                dataRepository: dataRepository,
                defaults: defaults,
                clock: .fixed(fixedDate)
            )
        } catch {
            preconditionFailure("Could not prepare the UI-test fixture: \(error)")
        }
    }

    /// The real statement file used by the import-rules UI test.
    ///
    /// The file picker itself belongs to iOS. Under the explicit UI-test launch
    /// flag, the app can pass this URL to the same reader, parser, preview, and
    /// save path that a file-picker result uses. Merely setting the seed or run ID
    /// is intentionally insufficient to expose a sandbox file to production code.
    static func importStatementURL(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard arguments.contains(launchArgument),
              environment[ledgerSeedVariable] == importRulesSeed
        else { return nil }

        let runID = sanitized(environment[runIDVariable] ?? "local")
        let url = fixtureDirectory(runID: runID)
            .appendingPathComponent(importRulesStatementFileName)

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func restoreBackupURL(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard arguments.contains(launchArgument),
              environment[ledgerSeedVariable] == LedgerSeed.restoreErase.rawValue else { return nil }
        let directory = fixtureDirectory(runID: sanitized(environment[runIDVariable] ?? "local"))
        let url = directory.appendingPathComponent("restore-backup.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func makeRestoreBackup() throws -> LedgerBackup {
        let eur = Currency("EUR")
        let date = Date(timeIntervalSince1970: 1_789_300_800)
        let bank = Account(id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000401")!),
                           name: "Restored Bank", kind: .asset, currency: eur)
        let groceries = Account(id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000402")!),
                                name: "Restored Groceries", kind: .expense)
        let salary = Account(id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000403")!),
                             name: "Restored Salary", kind: .income)
        var ledger = Ledger()
        for account in [bank, groceries, salary] { ledger.addAccount(account) }
        let expense = try Transaction.draftExpense(paidFrom: bank.id, category: groceries.id,
            amount: Money(25, currency: eur), date: date, memo: "Restored groceries")
        try ledger.addTransaction(expense)
        try ledger.finalizeTransaction(id: expense.id, now: date)
        let income = try Transaction.draftIncome(receivedIn: bank.id, source: salary.id,
            amount: Money(100, currency: eur), date: date, memo: "Restored salary")
        try ledger.addTransaction(income)
        var budget = Budget()
        try budget.setTarget(amount: Money(300, currency: eur), for: groceries.id,
                             from: BudgetPeriod(year: 2026, month: 9), in: ledger)
        return LedgerBackup(createdAt: date, ledger: ledger, budget: budget,
            classificationRules: [ClassificationRuleConfiguration(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
                needle: "RESTORED SHOP", counterpartyAccountID: groceries.id)])
    }

    private enum LedgerSeed: String {
        case standard
        case noActiveExpense = "no-active-expense"
        case importRules = "import-rules"
        case restoreErase = "restore-erase"
        case reconciliation
    }

    private static func makeLedger(seed: LedgerSeed) throws -> Ledger {
        let eur = Currency("EUR")
        let bankID = AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let eatingOutID = AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)

        var ledger = Ledger()
        ledger.addAccount(
            Account(
                id: bankID,
                name: seed == .importRules ? "Revolut" : "Fixture Bank",
                kind: .asset,
                currency: eur,
                sortOrder: 1
            )
        )
        switch seed {
        case .standard, .restoreErase:
            ledger.addAccount(
                Account(
                    id: eatingOutID,
                    name: "Eating out",
                    kind: .expense,
                    sortOrder: 2
                )
            )

        case .noActiveExpense:
            ledger.addAccount(
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000102")!),
                    name: "Fixture Savings",
                    kind: .asset,
                    currency: eur,
                    sortOrder: 2
                )
            )
            ledger.addAccount(
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000301")!),
                    name: "Fixture Salary",
                    kind: .income,
                    sortOrder: 3
                )
            )
            ledger.addAccount(
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000202")!),
                    name: "Archived dining",
                    kind: .expense,
                    status: .archived,
                    sortOrder: 4
                )
            )

        case .importRules:
            let accounts = [
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000200")!),
                    name: "Uncategorised",
                    kind: .expense,
                    sortOrder: 2
                ),
                Account(
                    id: eatingOutID,
                    name: "Groceries",
                    kind: .expense,
                    sortOrder: 3
                ),
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000202")!),
                    name: "Transport",
                    kind: .expense,
                    sortOrder: 4
                ),
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000203")!),
                    name: "Bank fees",
                    kind: .expense,
                    sortOrder: 5
                ),
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000301")!),
                    name: "Salary",
                    kind: .income,
                    sortOrder: 6
                ),
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000302")!),
                    name: "Other income",
                    kind: .income,
                    sortOrder: 7
                )
            ]

            for account in accounts {
                ledger.addAccount(account)
            }

        case .reconciliation:
            ledger.addAccount(
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000210")!),
                    name: "Reconciliation groceries",
                    kind: .expense,
                    sortOrder: 2
                )
            )
            ledger.addAccount(
                Account(
                    id: AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000310")!),
                    name: "Reconciliation salary",
                    kind: .income,
                    sortOrder: 3
                )
            )
            try seedReconciliationTransactions(into: &ledger, bankID: bankID, eur: eur)
        }
        return ledger
    }

    /// One cleared income, one pending expense, one draft, and one finalized
    /// entry dated the day after the fixed UI-test clock — chosen so the
    /// reconciliation screen's default day shows a known, checkable mismatch that
    /// a single confirm resolves to zero. See `ReconciliationUITests`.
    private static func seedReconciliationTransactions(
        into ledger: inout Ledger,
        bankID: AccountID,
        eur: Currency
    ) throws {
        let groceriesID = AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000210")!)
        let salaryID = AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000310")!)

        // Matches the fixed clock this fixture launches with (see `nowVariable`'s
        // default and the tests' explicit `ACCOUNTANT_UI_TEST_NOW`).
        let selectedDay = Date(timeIntervalSince1970: 1_789_300_800) // 2026-09-13 12:00:00 UTC

        // The final fractional second of the selected day. The old "+1 day, then
        // subtract one whole second" cutoff excluded this instant; only
        // `ReconciliationDate.endOfDay` includes it. Dating the one entry the UI
        // test confirms right on this edge is what makes the native journey
        // actually catch a cutoff regression, not just the unit tests.
        let lastInstantOfSelectedDay = selectedDay.addingTimeInterval(43_199.5) // 2026-09-13 23:59:59.5 UTC

        // Exactly the next midnight — one instant past the cutoff either way.
        let nextMidnight = selectedDay.addingTimeInterval(43_200) // 2026-09-14 00:00:00 UTC

        let income = try Transaction.draftIncome(
            receivedIn: bankID,
            source: salaryID,
            amount: Money(100, currency: eur),
            date: selectedDay.addingTimeInterval(-3 * 3600),
            memo: "Reconciliation salary"
        )
        try ledger.addTransaction(income)
        try ledger.finalizeTransaction(id: income.id, now: selectedDay)
        try ledger.setCleared(true, forAccount: bankID, in: income.id, now: selectedDay)

        // Left uncleared on purpose: this is the one entry the UI test confirms
        // to bring the difference to zero.
        let pendingExpense = try Transaction.draftExpense(
            paidFrom: bankID,
            category: groceriesID,
            amount: Money(25, currency: eur),
            date: lastInstantOfSelectedDay,
            memo: "Reconciliation groceries run"
        )
        try ledger.addTransaction(pendingExpense)
        try ledger.finalizeTransaction(id: pendingExpense.id, now: selectedDay)

        // Left as a draft on purpose: reconciliation excludes it, even though it
        // is dated within the selected day and appears in account activity.
        let draftExpense = try Transaction.draftExpense(
            paidFrom: bankID,
            category: groceriesID,
            amount: Money(10, currency: eur),
            date: selectedDay,
            memo: "Reconciliation coffee draft"
        )
        try ledger.addTransaction(draftExpense)

        // Finalized but dated exactly the next midnight: excluded by the
        // reconciliation cutoff, even though it counts in the account's balance.
        let nextDayExpense = try Transaction.draftExpense(
            paidFrom: bankID,
            category: groceriesID,
            amount: Money(5, currency: eur),
            date: nextMidnight,
            memo: "Reconciliation next-day fee"
        )
        try ledger.addTransaction(nextDayExpense)
        try ledger.finalizeTransaction(id: nextDayExpense.id, now: nextMidnight)
    }

    private static let importRulesStatementFileName = "revolut-import-rules.csv"

    private static let importRulesStatement = """
    Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
    Card Payment,Current,2026-09-02 17:42:10,2026-09-03 06:12:20,RIMI SUPERMARKET TALLINN,-24.60,0.40,EUR,COMPLETED,2975.00
    Transfer,Current,2026-09-04 08:00:00,2026-09-04 08:00:03,ACME PAYROLL SEPTEMBER,2450.00,0.00,EUR,COMPLETED,5425.00
    Card Payment,Current,2026-09-05 12:15:00,2026-09-05 12:15:07,RIMI SUPERMARKET REFUND,5.20,0.00,EUR,COMPLETED,5430.20
    Card Payment,Current,2026-09-07 19:10:00,2026-09-08 05:33:14,CITYBEE RIDE,-8.75,0.00,EUR,COMPLETED,5421.45
    Card Payment,Current,2026-09-09 09:01:00,2026-09-09 09:01:04,CORNER CAFE,-6.30,0.00,EUR,COMPLETED,5415.15
    """

    private static func writeImportRulesStatement(to directory: URL) throws {
        let url = directory.appendingPathComponent(importRulesStatementFileName)
        try Data(importRulesStatement.utf8).write(to: url, options: .atomic)
    }

    private static func fixtureDirectory(runID: String) -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseDirectory
            .appendingPathComponent("Accountant", isDirectory: true)
            .appendingPathComponent("UITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(scalars)).prefix(80)
        return result.isEmpty ? "local" : String(result)
    }

    private static func removeFixtureDirectory(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// Debug-only fault injection for the Stop retry journey. It rejects just one
/// normal snapshot save after a current-month target disappears, then delegates
/// every later save to the fixture's real JSON repository.
private actor FailFirstCurrentBudgetStopRepository: AppDataRepository {
    private let base: LocalJSONAppDataRepository
    private var lastSavedBudget = Budget()
    private var didFail = false
    private let currentPeriod = BudgetPeriod(year: 2026, month: 9)

    init(base: LocalJSONAppDataRepository) {
        self.base = base
    }

    func load() async -> AppDataLoadResult {
        let result = await base.load()
        lastSavedBudget = result.data.budget
        return result
    }

    func save(_ data: LedgerBackup) async throws {
        if !didFail && removesCurrentTarget(from: lastSavedBudget, in: data.budget) {
            didFail = true
            throw SyntheticBudgetStopSaveError()
        }

        try await base.save(data)
        lastSavedBudget = data.budget
    }

    func replaceForRecovery(_ data: LedgerBackup) async throws {
        try await base.replaceForRecovery(data)
        lastSavedBudget = data.budget
    }

    func completeRecovery() async throws {
        try await base.completeRecovery()
    }

    private func removesCurrentTarget(from previous: Budget, in submitted: Budget) -> Bool {
        previous.targets(in: currentPeriod).contains { previousTarget in
            submitted.target(for: previousTarget.accountID, in: currentPeriod) == nil
        }
    }
}

private struct SyntheticBudgetStopSaveError: LocalizedError {
    var errorDescription: String? { "Synthetic UI-test budget save failure." }
}
#endif
