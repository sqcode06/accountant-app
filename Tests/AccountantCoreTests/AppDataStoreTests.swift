import Foundation
import XCTest
@testable import AccountantCore

final class AppDataStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-data-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var ledgerURL: URL { directory.appendingPathComponent("ledger.json") }
    private var budgetURL: URL { directory.appendingPathComponent("budget.json") }
    private var rulesURL: URL { directory.appendingPathComponent("classification-rules.json") }

    private func fixture() throws -> LedgerBackup {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(groceries)
        let date = Date(timeIntervalSince1970: 1_709_634_600.123456)
        let transaction = Transaction(
            date: date,
            memo: "Rimi",
            postings: [
                Posting(accountID: bank.id, money: Money(-12.34, currency: eur), cleared: true, role: .statement),
                Posting(accountID: groceries.id, money: Money(12.34, currency: eur), cleared: false, role: .counterparty)
            ],
            createdAt: Date(timeIntervalSince1970: 1_709_634_601.234567),
            updatedAt: Date(timeIntervalSince1970: 1_709_634_602.345678),
            origin: TransactionOrigin(source: "fixture", externalID: "entry-1")
        )
        try ledger.addTransaction(transaction)

        let budget = Budget(targets: [BudgetTarget(
            accountID: groceries.id, amount: Money(100, currency: eur),
            effectiveFrom: BudgetPeriod(year: 2026, month: 1)
        )])
        return LedgerBackup(
            createdAt: Date(timeIntervalSince1970: 1_709_700_000.654321),
            ledger: ledger, budget: budget,
            classificationRules: [ClassificationRuleConfiguration(
                needle: "Rimi", counterpartyAccountID: groceries.id, cleanedMemo: "Groceries"
            )]
        )
    }

    private func seedLegacy(_ data: LedgerBackup, version: Int = 4) throws {
        try JSONLedgerStore(fileURL: ledgerURL).save(data.ledger)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: ledgerURL)) as? [String: Any])
        object["schemaVersion"] = version
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: ledgerURL)
        try JSONFileStore<Budget>(fileURL: budgetURL, fallback: { Budget() }).save(data.budget)
        try JSONFileStore<[ClassificationRuleConfiguration]>(fileURL: rulesURL, fallback: { [] })
            .save(data.classificationRules)
    }

    private func schemaVersion() throws -> Int {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: ledgerURL)) as? [String: Any])
        return try XCTUnwrap(object["schemaVersion"] as? Int)
    }

    private func assertData(_ actual: LedgerBackup, equals expected: LedgerBackup, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.ledger, expected.ledger, file: file, line: line)
        XCTAssertEqual(actual.budget, expected.budget, file: file, line: line)
        XCTAssertEqual(actual.classificationRules, expected.classificationRules, file: file, line: line)
    }

    func testLegacyVersionsLoadAllComponentsThenFirstSaveMigratesToSchemaFive() throws {
        let expected = try fixture()
        for version in 1...4 {
            let folder = directory.appendingPathComponent("v\(version)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let originalDirectory = directory!
            directory = folder
            try seedLegacy(expected, version: version)

            let store = AppDataStore(directory: folder)
            let loaded = store.load()
            XCTAssertTrue(loaded.damage.isEmpty, "v\(version)")
            assertData(loaded.data, equals: expected)
            try store.save(loaded.data)
            XCTAssertEqual(try schemaVersion(), 5)
            assertData(AppDataStore(directory: folder).load().data, equals: expected)
            directory = originalDirectory
        }
    }

    func testFreshInstallWritesSchemaFiveAndPreservesExactStoredDates() throws {
        let data = try fixture()
        let store = AppDataStore(directory: directory)
        XCTAssertTrue(store.load().damage.isEmpty)
        try store.save(data)
        XCTAssertEqual(try schemaVersion(), 5)
        let reloaded = store.load()
        XCTAssertTrue(reloaded.damage.isEmpty)
        assertData(reloaded.data, equals: data)
        XCTAssertEqual(
            reloaded.data.ledger.transactions[0].date.timeIntervalSince1970,
            data.ledger.transactions[0].date.timeIntervalSince1970
        )
    }

    func testCommitFaultsLeaveEitherTheOldOrTheCompleteNewSnapshot() throws {
        let old = try fixture()
        let replacements = [try fixture(), LedgerBackup(ledger: Ledger())]

        for checkpoint in [AppDataStore.Checkpoint.beforeEncoding, .beforeCommit, .afterCommit] {
            for (index, replacement) in replacements.enumerated() {
                let folder = directory.appendingPathComponent("current-\(checkpoint)-\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try AppDataStore(directory: folder).save(old)
                let failing = AppDataStore(directory: folder) { point in
                    if point == checkpoint { throw InjectedFault() }
                }
                XCTAssertThrowsError(try failing.save(replacement), "\(checkpoint)")
                let reopened = AppDataStore(directory: folder).load()
                XCTAssertTrue(reopened.damage.isEmpty)
                assertData(reopened.data, equals: checkpoint == .afterCommit ? replacement : old)
            }
        }
    }

    func testCommitFaultMatrixAlsoMigratesLegacyFilesAtomically() throws {
        let old = try fixture()
        let replacements = [try fixture(), LedgerBackup(ledger: Ledger())]
        for checkpoint in [AppDataStore.Checkpoint.beforeEncoding, .beforeCommit, .afterCommit] {
            for (index, replacement) in replacements.enumerated() {
                let folder = directory.appendingPathComponent("legacy-\(checkpoint)-\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let saved = directory!
                directory = folder
                try seedLegacy(old)
                directory = saved
                let failing = AppDataStore(directory: folder) { point in
                    if point == checkpoint { throw InjectedFault() }
                }
                XCTAssertThrowsError(try failing.save(replacement))
                let reopened = AppDataStore(directory: folder).load()
                XCTAssertTrue(reopened.damage.isEmpty)
                assertData(reopened.data, equals: checkpoint == .afterCommit ? replacement : old)
            }
        }
    }

    func testRecoveryProtectsCorruptPrimaryUntilCompletionAndRetainsOriginalBytes() throws {
        let original = Data("damaged primary bytes".utf8)
        try original.write(to: ledgerURL)
        let store = AppDataStore(directory: directory)
        let damaged = store.load()
        let record = try XCTUnwrap(damaged.damage.first { $0.originalURL == ledgerURL })
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)

        let replacement = try fixture()
        try store.replaceForRecovery(replacement)
        XCTAssertFalse(AppDataStore(directory: directory).load().damage.isEmpty)
        try store.completeRecovery()
        let restored = AppDataStore(directory: directory).load()
        XCTAssertTrue(restored.damage.isEmpty)
        assertData(restored.data, equals: replacement)
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)
    }

    func testDamagedLegacyLedgerRetainsQuarantineAndDoesNotUnlockCompanionsEarly() throws {
        let data = try fixture()
        try JSONFileStore<Budget>(fileURL: budgetURL, fallback: { Budget() }).save(data.budget)
        try JSONFileStore<[ClassificationRuleConfiguration]>(fileURL: rulesURL, fallback: { [] }).save(data.classificationRules)
        let original = Data("corrupt legacy ledger".utf8)
        try original.write(to: ledgerURL)

        let store = AppDataStore(directory: directory)
        let damage = store.load()
        let record = try XCTUnwrap(damage.damage.first { $0.originalURL == ledgerURL })
        try store.replaceForRecovery(data)
        XCTAssertFalse(store.load().damage.isEmpty)
        try store.completeRecovery()
        XCTAssertTrue(store.load().damage.isEmpty)
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)
    }

    func testRecoveryCheckpointMatrixStaysLockedUntilCompletionHasDurablyFinished() throws {
        let replacement = try fixture()
        for legacyCompanions in [false, true] {
            for checkpoint in AppDataStore.Checkpoint.allCases {
                let folder = directory.appendingPathComponent(
                    "recovery-\(legacyCompanions ? "legacy" : "combined")-\(checkpoint.rawValue)",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let original = Data("damaged \(checkpoint.rawValue) \(legacyCompanions)".utf8)
                let ledger = folder.appendingPathComponent("ledger.json")
                try original.write(to: ledger)
                if legacyCompanions {
                    try JSONFileStore<Budget>(fileURL: folder.appendingPathComponent("budget.json"), fallback: { Budget() })
                        .save(replacement.budget)
                    try JSONFileStore<[ClassificationRuleConfiguration]>(
                        fileURL: folder.appendingPathComponent("classification-rules.json"), fallback: { [] }
                    ).save(replacement.classificationRules)
                }

                let store = AppDataStore(directory: folder) { point in
                    if point == checkpoint { throw InjectedFault() }
                }
                let record = try XCTUnwrap(store.load().damage.first { $0.originalURL == ledger })
                var replacementCompleted = false
                do {
                    try store.replaceForRecovery(replacement)
                    replacementCompleted = true
                } catch {
                    // A failed replacement must retain the recovery lock.
                }
                if replacementCompleted {
                    XCTAssertThrowsError(try store.completeRecovery())
                }

                let reloaded = AppDataStore(directory: folder).load()
                if checkpoint == .afterRecoveryCompletion {
                    XCTAssertTrue(reloaded.damage.isEmpty, "\(legacyCompanions) \(checkpoint)")
                    assertData(reloaded.data, equals: replacement)
                } else {
                    XCTAssertFalse(reloaded.damage.isEmpty, "\(legacyCompanions) \(checkpoint)")
                }
                XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)
            }
        }
    }

    func testCombinedSnapshotRejectsRequiredFieldFailuresAndUnsupportedVersions() throws {
        let data = try fixture()
        for mutation in ["missingBudget", "nullRules", "futureVersion", "duplicateRules", "invalidBudget"] {
            let folder = directory.appendingPathComponent(mutation, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try AppDataStore(directory: folder).save(data)
            let url = folder.appendingPathComponent("ledger.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            switch mutation {
            case "missingBudget": object.removeValue(forKey: "budget")
            case "nullRules": object["classificationRules"] = NSNull()
            case "duplicateRules":
                let rule = data.classificationRules[0]
                object["classificationRules"] = try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode([rule, rule])
                )
            case "invalidBudget":
                let invalid = Budget(targets: [BudgetTarget(
                    accountID: AccountID(), amount: Money(10, currency: Currency("EUR")),
                    effectiveFrom: BudgetPeriod(year: 2026, month: 1)
                )])
                object["budget"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(invalid))
            default: object["schemaVersion"] = 99
            }
            try JSONSerialization.data(withJSONObject: object).write(to: url)
            let reopened = AppDataStore(directory: folder).load()
            XCTAssertFalse(reopened.damage.isEmpty, mutation)
            XCTAssertThrowsError(try AppDataStore(directory: folder).save(data), mutation)
        }
    }

    func testLegacySemanticInvalidityQuarantinesEverySourceBeforeReplacement() throws {
        let data = try fixture()
        for inconsistency in ["invalid-budget", "duplicate-rule"] {
            let folder = directory.appendingPathComponent(inconsistency, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let savedDirectory = directory!
            directory = folder
            try seedLegacy(data)
            if inconsistency == "invalid-budget" {
                try JSONFileStore<Budget>(fileURL: budgetURL, fallback: { Budget() }).save(Budget(targets: [
                    BudgetTarget(
                        accountID: AccountID(), amount: Money(10, currency: Currency("EUR")),
                        effectiveFrom: BudgetPeriod(year: 2026, month: 1)
                    )
                ]))
            } else {
                let rule = data.classificationRules[0]
                try JSONFileStore<[ClassificationRuleConfiguration]>(fileURL: rulesURL, fallback: { [] })
                    .save([rule, rule])
            }
            let originals = try [ledgerURL, budgetURL, rulesURL].reduce(into: [URL: Data]()) {
                $0[$1] = try Data(contentsOf: $1)
            }
            directory = savedDirectory

            let store = AppDataStore(directory: folder)
            let damaged = store.load()
            XCTAssertFalse(damaged.damage.isEmpty, inconsistency)
            for (url, original) in originals {
                let record = try XCTUnwrap(damaged.damage.first { $0.originalURL == url })
                XCTAssertTrue(record.didMove, "\(inconsistency): \(url.lastPathComponent)")
                XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)
            }

            let fresh = LedgerBackup(ledger: Ledger())
            try store.replaceForRecovery(fresh)
            try store.completeRecovery()
            let relaunched = AppDataStore(directory: folder).load()
            XCTAssertTrue(relaunched.damage.isEmpty, inconsistency)
            assertData(relaunched.data, equals: fresh)
        }
    }

    func testStaleNonzeroRuleReferencesRemainSupported() throws {
        let data = try fixture()
        let stale = LedgerBackup(
            createdAt: data.createdAt, ledger: data.ledger, budget: data.budget,
            classificationRules: [ClassificationRuleConfiguration(
                needle: "historical", counterpartyAccountID: AccountID(), cleanedMemo: "old"
            )]
        )
        try AppDataStore(directory: directory).save(stale)
        let loaded = AppDataStore(directory: directory).load()
        XCTAssertTrue(loaded.damage.isEmpty)
        assertData(loaded.data, equals: stale)
    }

    func testDamagedLegacyCompanionRecoveryAlsoProtectsHealthyPrimaryBytes() throws {
        let legacy = try fixture()
        try seedLegacy(legacy)
        let originalLedger = try Data(contentsOf: ledgerURL)
        let originalBudget = Data("damaged legacy budget".utf8)
        try originalBudget.write(to: budgetURL)

        let store = AppDataStore(directory: directory)
        let damaged = store.load()
        XCTAssertEqual(damaged.damage.map(\.originalURL), [budgetURL])
        let budgetRecord = try XCTUnwrap(damaged.damage.first)
        XCTAssertEqual(try Data(contentsOf: budgetRecord.quarantinedURL), originalBudget)

        let fresh = LedgerBackup(ledger: Ledger())
        try store.replaceForRecovery(fresh)
        try store.completeRecovery()

        let ledgerQuarantine = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("ledger.unreadable-") }
        )
        XCTAssertEqual(try Data(contentsOf: ledgerQuarantine), originalLedger)
        let relaunched = AppDataStore(directory: directory).load()
        XCTAssertTrue(relaunched.damage.isEmpty)
        assertData(relaunched.data, equals: fresh)
    }

    func testUnwriteablePrimaryRecoveryMarkerRefusesReplacementAndPreservesBytes() throws {
        let original = Data("cannot safely move this primary".utf8)
        try original.write(to: ledgerURL)
        let markerURL = directory.appendingPathComponent("ledger.recovery.json")
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: false)

        let store = AppDataStore(directory: directory)
        let damaged = store.load()
        XCTAssertFalse(damaged.damage.isEmpty)
        XCTAssertThrowsError(try store.replaceForRecovery(LedgerBackup(ledger: Ledger())))
        XCTAssertEqual(try Data(contentsOf: ledgerURL), original)
    }

    func testSchemaFiveIgnoresCorruptCompanionsAndOlderLedgerStoreRejectsIt() throws {
        let data = try fixture()
        let store = AppDataStore(directory: directory)
        try store.save(data)
        try Data("bad companion".utf8).write(to: budgetURL)
        try Data("bad marker".utf8).write(to: directory.appendingPathComponent("classification-rules.recovery.json"))
        XCTAssertTrue(store.load().damage.isEmpty)

        let empty = LedgerBackup(ledger: Ledger())
        try store.save(empty)
        let reloaded = AppDataStore(directory: directory).load()
        XCTAssertTrue(reloaded.damage.isEmpty)
        assertData(reloaded.data, equals: empty)
        guard case .unreadable = JSONLedgerStore(fileURL: ledgerURL).loadOutcome() else {
            return XCTFail("Older ledger readers must reject schema 5")
        }
    }

    func testUnresolvedPrimaryMarkerNeverFallsBackToCompanionsOrUnlocks() throws {
        let legacy = try fixture()
        try JSONFileStore<Budget>(fileURL: budgetURL, fallback: { Budget() }).save(legacy.budget)
        try JSONFileStore<[ClassificationRuleConfiguration]>(fileURL: rulesURL, fallback: { [] }).save(legacy.classificationRules)
        try Data("corrupt primary".utf8).write(to: ledgerURL)
        let first = AppDataStore(directory: directory).load()
        XCTAssertFalse(first.damage.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerURL.path))
        let relaunched = AppDataStore(directory: directory).load()
        XCTAssertFalse(relaunched.damage.isEmpty)
        XCTAssertThrowsError(try AppDataStore(directory: directory).save(legacy)) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .recoveryUnresolved)
        }
    }

    func testMissingResolvedReplacementCannotReviveLegacyRules() throws {
        let rules = [ClassificationRuleConfiguration(needle: "Old rule", cleanedMemo: "Old")]
        try JSONFileStore(fileURL: rulesURL) { [ClassificationRuleConfiguration]() }.save(rules)
        try Data("original corrupt primary".utf8).write(to: ledgerURL)
        let store = AppDataStore(directory: directory)
        XCTAssertFalse(store.load().damage.isEmpty)
        try store.replaceForRecovery(LedgerBackup(ledger: Ledger()))
        try store.completeRecovery()
        try FileManager.default.removeItem(at: ledgerURL)
        XCTAssertFalse(AppDataStore(directory: directory).load().damage.isEmpty)
        XCTAssertThrowsError(try store.save(LedgerBackup(ledger: Ledger())))
        try store.replaceForRecovery(LedgerBackup(ledger: Ledger()))
        try store.completeRecovery()
        XCTAssertTrue(store.load().damage.isEmpty)
        XCTAssertTrue(store.load().data.classificationRules.isEmpty)
    }
}

private struct InjectedFault: Error {}
