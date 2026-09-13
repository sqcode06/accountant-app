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

    let ledgerRepository: LocalJSONLedgerRepository
    let classificationRuleRepository: LocalJSONClassificationRuleRepository
    let budgetRepository: LocalJSONBudgetRepository
    let defaults: UserDefaults
    let clock: AppClock

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppUITestFixture? {
        guard arguments.contains(launchArgument) else { return nil }

        let rawRunID = environment[runIDVariable] ?? "local"
        let runID = sanitized(rawRunID)
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let fixtureDirectory = baseDirectory
            .appendingPathComponent("Accountant", isDirectory: true)
            .appendingPathComponent("UITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)

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
            if !FileManager.default.fileExists(atPath: ledgerURL.path) {
                try JSONLedgerStore(fileURL: ledgerURL).save(makeLedger())
            }

            // Avoid onboarding and the notification permission prompt. These are
            // tested separately from the accounting workflow.
            defaults.set("completed", forKey: "onboardingStatus")
            defaults.set(true, forKey: "reviewReminderDidAskPermission")
            defaults.set(false, forKey: "reviewReminderEnabled")

            let fixedDate = environment[nowVariable]
                .flatMap(ISO8601DateFormatter().date(from:))
                ?? Date(timeIntervalSince1970: 1_789_300_800) // 2026-09-13 12:00 UTC

            return AppUITestFixture(
                ledgerRepository: LocalJSONLedgerRepository(fileURL: ledgerURL),
                classificationRuleRepository: LocalJSONClassificationRuleRepository(
                    fileURL: fixtureDirectory.appendingPathComponent("classification-rules.json")
                ),
                budgetRepository: LocalJSONBudgetRepository(
                    fileURL: fixtureDirectory.appendingPathComponent("budget.json")
                ),
                defaults: defaults,
                clock: .fixed(fixedDate)
            )
        } catch {
            preconditionFailure("Could not prepare the UI-test fixture: \(error)")
        }
    }

    private static func makeLedger() -> Ledger {
        let eur = Currency("EUR")
        let bankID = AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let eatingOutID = AccountID(UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)

        var ledger = Ledger()
        ledger.addAccount(
            Account(
                id: bankID,
                name: "Fixture Bank",
                kind: .asset,
                currency: eur,
                sortOrder: 1
            )
        )
        ledger.addAccount(
            Account(
                id: eatingOutID,
                name: "Eating out",
                kind: .expense,
                sortOrder: 2
            )
        )
        return ledger
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
#endif
