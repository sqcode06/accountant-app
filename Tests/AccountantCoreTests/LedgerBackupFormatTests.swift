import XCTest
@testable import AccountantCore

/// The backup document.
///
/// The property under test throughout is the only one that matters: what comes
/// back out is what went in. A backup that decodes without error but drops the
/// budget, rounds a date, or silently loses drafts is worse than one that fails
/// loudly, because you find out at the moment you needed it.
final class LedgerBackupFormatTests: XCTestCase {

    private let eur = Currency("EUR")

    private func makeBackup() throws -> (
        backup: LedgerBackup,
        bank: Account,
        groceries: Account,
        draft: Transaction
    ) {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let confirmed = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(string: "42.50")!, currency: eur),
            date: Date(timeIntervalSince1970: 1_709_634_600),
            memo: "Rimi"
        )
        try ledger.addTransaction(confirmed)
        try ledger.finalizeTransaction(id: confirmed.id)

        let draft = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(string: "7.25")!, currency: eur),
            date: Date(timeIntervalSince1970: 1_709_700_000),
            memo: "Coffee"
        )
        try ledger.addTransaction(draft)

        var budget = Budget()
        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: groceries.id,
            from: BudgetPeriod(year: 2024, month: 3),
            in: ledger
        )

        let rule = ClassificationRuleConfiguration(
            needle: "RIMI",
            counterpartyAccountID: groceries.id,
            cleanedMemo: "Rimi"
        )

        let backup = LedgerBackup(
            createdAt: Date(timeIntervalSince1970: 1_709_800_000),
            ledger: ledger,
            budget: budget,
            classificationRules: [rule]
        )

        return (backup, bank, groceries, draft)
    }

    // MARK: - Round trip

    func testEverythingSurvivesARoundTrip() throws {
        let (backup, bank, groceries, _) = try makeBackup()

        let restored = try LedgerBackupCoder.decode(LedgerBackupCoder.encode(backup))

        XCTAssertEqual(restored.formatVersion, LedgerBackup.currentFormatVersion)
        XCTAssertEqual(restored.createdAt, backup.createdAt)

        // Ledger
        XCTAssertEqual(restored.ledger.accounts.count, 2)
        XCTAssertEqual(restored.ledger.accounts[bank.id]?.name, "Swedbank")
        XCTAssertEqual(restored.ledger.accounts[bank.id]?.currency, eur)
        XCTAssertEqual(restored.ledger.transactions.count, 2)
        XCTAssertEqual(
            restored.ledger.balance(of: bank.id, currency: eur).amount,
            Decimal(string: "-49.75")
        )

        // Budget — the half a ledger-only backup used to lose.
        XCTAssertEqual(restored.budget.targets.count, 1)
        XCTAssertEqual(
            restored.budget.target(for: groceries.id, in: BudgetPeriod(year: 2024, month: 3))?.amount,
            Money(Decimal(300), currency: eur)
        )

        // Rules — the other half.
        XCTAssertEqual(restored.classificationRules.count, 1)
        XCTAssertEqual(restored.classificationRules.first?.needle, "RIMI")
        XCTAssertEqual(restored.classificationRules.first?.counterpartyAccountID, groceries.id)
    }

    /// Draft and confirmed have to come back as they went in.
    ///
    /// Restoring a draft as confirmed would silently mark unreviewed guesses as
    /// checked, which is the one thing the review flow exists to prevent.
    func testTransactionStateSurvives() throws {
        let (backup, _, _, draft) = try makeBackup()

        let restored = try LedgerBackupCoder.decode(LedgerBackupCoder.encode(backup))

        let restoredDraft = try XCTUnwrap(restored.ledger.transactions.first { $0.id == draft.id })
        XCTAssertEqual(restoredDraft.state, .draft)
        XCTAssertEqual(restored.ledger.draftTransactions().count, 1)
        XCTAssertEqual(restored.ledger.transactions.filter { $0.state == .finalized }.count, 1)
    }

    /// Dates survive to the precision the format actually stores.
    ///
    /// Dates go out as the hex bit pattern of `timeIntervalSince1970`, so that
    /// value round-trips bit-for-bit. `Date` stores `timeIntervalSinceReferenceDate`
    /// internally, though, and converting between the two epochs is a `Double`
    /// addition and subtraction near 1.7e9 — which can land one unit in the last
    /// place away from where it started. Measured worst case over 200k samples of
    /// the current time: about 119 nanoseconds, and usually exactly zero.
    ///
    /// That is harmless here and worth writing down rather than leaving as a
    /// surprise. `createdAt` breaks ties in `allTransactionsSorted` only between
    /// transactions sharing a date, two entries would have to be created within
    /// 119ns of each other to be affected, and the UUID tiebreak below it keeps
    /// the order deterministic regardless. Encoding the reference-date interval
    /// instead would be exact, but every ledger.json already on a device stores
    /// the 1970 form — reading one as the other would misdate it by 31 years, so
    /// that change needs a format version and a migration, not a quiet swap.
    ///
    /// This is a property of the existing ledger store, inherited deliberately:
    /// the backup shares its date strategy precisely so the two cannot drift.
    func testDatesSurviveToStoredPrecision() throws {
        var ledger = Ledger()
        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        // Deliberately awkward: not a whole number of seconds.
        let awkward = Date(timeIntervalSince1970: 1_709_634_600.123456)
        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(10), currency: eur),
            date: awkward
        )
        try ledger.addTransaction(tx)

        let backup = LedgerBackup(ledger: ledger)
        let restored = try LedgerBackupCoder.decode(LedgerBackupCoder.encode(backup))

        let restoredTx = try XCTUnwrap(restored.ledger.transactions.first)

        // What the format actually guarantees, and does guarantee exactly.
        XCTAssertEqual(restoredTx.date.timeIntervalSince1970, awkward.timeIntervalSince1970)
        XCTAssertEqual(
            restoredTx.createdAt.timeIntervalSince1970,
            tx.createdAt.timeIntervalSince1970
        )
        XCTAssertEqual(
            restoredTx.updatedAt.timeIntervalSince1970,
            tx.updatedAt.timeIntervalSince1970
        )

        // And the residue on `Date` itself stays far below anything that could
        // reorder two entries.
        XCTAssertEqual(
            restoredTx.createdAt.timeIntervalSinceReferenceDate,
            tx.createdAt.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
    }

    func testRestoredLedgerIsStillUsable() throws {
        let (backup, bank, groceries, _) = try makeBackup()

        var restored = try LedgerBackupCoder.decode(LedgerBackupCoder.encode(backup)).ledger

        // A restore that produces a read-only museum piece is not a restore.
        let fresh = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(5), currency: eur),
            date: Date(timeIntervalSince1970: 1_709_800_000)
        )

        XCTAssertNoThrow(try restored.addTransaction(fresh))
        XCTAssertEqual(restored.transactions.count, 3)
    }

    // MARK: - Tolerance

    func testBackupWithoutBudgetOrRulesDecodes() throws {
        // A perfectly good backup of an app where neither had been used yet.
        let json = """
        {
          "formatVersion": 1,
          "createdAt": "41c97d9e2a800000",
          "ledger": { "accounts": [], "transactions": [] }
        }
        """

        let backup = try LedgerBackupCoder.decode(Data(json.utf8))

        XCTAssertTrue(backup.ledger.accounts.isEmpty)
        XCTAssertTrue(backup.budget.targets.isEmpty)
        XCTAssertTrue(backup.classificationRules.isEmpty)
    }

    // MARK: - Refusal

    func testBackupFromANewerAppIsRefusedByVersion() throws {
        let (backup, _, _, _) = try makeBackup()

        let fromTheFuture = LedgerBackup(
            formatVersion: LedgerBackup.currentFormatVersion + 1,
            createdAt: backup.createdAt,
            ledger: backup.ledger,
            budget: backup.budget,
            classificationRules: backup.classificationRules
        )

        let data = try LedgerBackupCoder.encode(fromTheFuture)

        XCTAssertThrowsError(try LedgerBackupCoder.decode(data)) { error in
            XCTAssertEqual(
                error as? LedgerBackupError,
                .unsupportedFormatVersion(LedgerBackup.currentFormatVersion + 1)
            )
        }
    }

    func testGarbageIsRefusedAsUnreadable() {
        XCTAssertThrowsError(try LedgerBackupCoder.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? LedgerBackupError, .unreadable)
        }
    }

    /// A ledger.json is not a backup, and picking one by mistake is easy — they
    /// sit next to each other and both are JSON.
    func testARawLedgerFileIsNotAcceptedAsABackup() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("ledger.json")
        let store = JSONLedgerStore(fileURL: fileURL)
        try store.save(Ledger())

        let data = try Data(contentsOf: fileURL)

        XCTAssertThrowsError(try LedgerBackupCoder.decode(data)) { error in
            XCTAssertEqual(error as? LedgerBackupError, .unreadable)
        }
    }

    // MARK: - Summary

    func testSummaryDescribesTheFileBeforeAnythingIsOverwritten() throws {
        let (backup, _, _, _) = try makeBackup()

        let summary = try LedgerBackupCoder.summarize(LedgerBackupCoder.encode(backup))

        XCTAssertEqual(summary.createdAt, backup.createdAt)
        XCTAssertEqual(summary.accountCount, 2)
        XCTAssertEqual(summary.transactionCount, 2)
        XCTAssertEqual(summary.draftCount, 1)
        XCTAssertEqual(summary.budgetTargetCount, 1)
        XCTAssertEqual(summary.classificationRuleCount, 1)
    }
}
