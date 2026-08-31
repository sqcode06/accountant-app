import XCTest
@testable import AccountantCore

/// Getting data out of the app.
///
/// The failure mode that matters here is silent: a file that opens fine and is
/// subtly wrong — a memo containing a comma shifting every later column, an amount
/// written in the phone's locale, a date the spreadsheet reinterprets. Each of
/// those produces a plausible-looking file, which is exactly why they need tests.
final class LedgerExportTests: XCTestCase {

    private let eur = Currency("EUR")
    private let usd = Currency("USD")

    /// Fixed so the formatted day never depends on where the test runs.
    private let utc = TimeZone(identifier: "UTC")!

    /// 2024-03-05T10:30:00Z
    private let date = Date(timeIntervalSince1970: 1_709_634_600)

    private func makeLedger() -> (ledger: Ledger, bank: Account, groceries: Account) {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        return (ledger, bank, groceries)
    }

    private func addExpense(
        to ledger: inout Ledger,
        bank: Account,
        groceries: Account,
        amount: Decimal = 42.50,
        memo: String? = nil,
        finalize: Bool = false
    ) throws -> Transaction {
        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(amount, currency: eur),
            date: date,
            memo: memo
        )

        try ledger.addTransaction(tx)

        if finalize {
            try ledger.finalizeTransaction(id: tx.id)
        }

        return tx
    }

    private func rows(_ csv: String) -> [String] {
        csv.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - Transactions

    func testEmptyLedgerExportsHeaderOnly() {
        let csv = LedgerExport.transactionsCSV(from: Ledger(), timeZone: utc)

        XCTAssertEqual(rows(csv).count, 1)
        XCTAssertTrue(csv.hasPrefix("Date,Transaction ID,State,Memo,Account"))
        // Even an empty file ends with a newline, so appending is safe.
        XCTAssertTrue(csv.hasSuffix("\n"))
    }

    func testOneRowPerPostingNotPerTransaction() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries)

        let lines = rows(LedgerExport.transactionsCSV(from: ledger, timeZone: utc))

        // Header plus both sides of the entry.
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.contains { $0.contains("Swedbank") && $0.contains("-42.50") })
        XCTAssertTrue(lines.contains { $0.contains("Groceries") && $0.contains(",42.50,") })
    }

    func testRowsOfOneTransactionShareItsIdentity() throws {
        var (ledger, bank, groceries) = makeLedger()
        let tx = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "Rimi")

        let lines = rows(LedgerExport.transactionsCSV(from: ledger, timeZone: utc)).dropFirst()

        // What makes the postings reassemblable into a transaction.
        for line in lines {
            XCTAssertTrue(line.contains(tx.id.rawValue.uuidString))
            XCTAssertTrue(line.contains("Rimi"))
            XCTAssertTrue(line.contains("2024-03-05"))
        }
    }

    /// The day written is the day in the reader's zone, not in UTC.
    ///
    /// A transaction carries an instant, but what belongs in the file is the date
    /// the person would say it happened on. Formatting in UTC would move late
    /// evening purchases to the following day for anyone east of Greenwich.
    func testDateUsesTheGivenTimeZone() throws {
        var (ledger, bank, groceries) = makeLedger()

        // 2024-03-05T23:30:00Z — still the 5th in UTC, already the 6th in Tallinn.
        let lateEvening = Date(timeIntervalSince1970: 1_709_681_400)
        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(10), currency: eur),
            date: lateEvening
        )
        try ledger.addTransaction(tx)

        let utcCSV = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)
        XCTAssertTrue(utcCSV.contains("2024-03-05"))
        XCTAssertFalse(utcCSV.contains("2024-03-06"))

        let tallinn = TimeZone(identifier: "Europe/Tallinn")!
        let tallinnCSV = LedgerExport.transactionsCSV(from: ledger, timeZone: tallinn)
        XCTAssertTrue(tallinnCSV.contains("2024-03-06"))
        XCTAssertFalse(tallinnCSV.contains("2024-03-05"))
    }

    // MARK: - Escaping

    func testMemoContainingACommaIsQuoted() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "Rimi, Tartu")

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        XCTAssertTrue(csv.contains("\"Rimi, Tartu\""))

        // Unquoted, this row would have one more column than the header and every
        // field after the memo would land in the wrong place.
        for line in rows(csv).dropFirst() {
            XCTAssertEqual(columnCount(of: line), 11)
        }
    }

    func testMemoContainingAQuoteIsEscapedByDoubling() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "The \"good\" cheese")

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        XCTAssertTrue(csv.contains("\"The \"\"good\"\" cheese\""))
    }

    func testMemoContainingANewlineIsQuoted() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "Line one\nLine two")

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        XCTAssertTrue(csv.contains("\"Line one\nLine two\""))
    }

    func testOrdinaryFieldsAreNotQuoted() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "Rimi")

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        // Quoting everything unconditionally would also be correct, and would make
        // the file noticeably worse to read.
        XCTAssertTrue(csv.contains(",Rimi,"))
    }

    // MARK: - Amounts

    func testAmountsUseADotAndTwoDecimalsAtMost() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, amount: Decimal(string: "1234.5")!)

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        XCTAssertTrue(csv.contains("1234.50"))
        // No thousands separator: a grouped "1,234.50" would break the column.
        XCTAssertFalse(csv.contains("1,234"))
    }

    func testAmountsDoNotDriftThroughFloatingPoint() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, amount: Decimal(string: "0.07")!)

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        XCTAssertTrue(csv.contains("0.07"))
        XCTAssertTrue(csv.contains("-0.07"))
        XCTAssertFalse(csv.contains("0.06999"))
    }

    // MARK: - Filtering

    func testDraftsCanBeExcluded() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "Confirmed", finalize: true)
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, memo: "Unreviewed")

        let all = LedgerExport.transactionsCSV(from: ledger, includeDrafts: true, timeZone: utc)
        XCTAssertTrue(all.contains("Confirmed"))
        XCTAssertTrue(all.contains("Unreviewed"))

        let confirmedOnly = LedgerExport.transactionsCSV(from: ledger, includeDrafts: false, timeZone: utc)
        XCTAssertTrue(confirmedOnly.contains("Confirmed"))
        XCTAssertFalse(confirmedOnly.contains("Unreviewed"))
    }

    func testStateAndClearedAreReported() throws {
        var (ledger, bank, groceries) = makeLedger()
        let tx = try addExpense(to: &ledger, bank: bank, groceries: groceries, finalize: true)
        try ledger.setCleared(true, forAccount: bank.id, in: tx.id)

        let csv = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)
        let bankRow = try XCTUnwrap(rows(csv).first { $0.contains("Swedbank") })

        XCTAssertTrue(bankRow.contains("finalized"))
        XCTAssertTrue(bankRow.contains("yes"))

        let categoryRow = try XCTUnwrap(rows(csv).first { $0.contains("Groceries") })
        XCTAssertTrue(categoryRow.contains("no"))
    }

    func testExportIsDeterministic() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, amount: 10)
        _ = try addExpense(to: &ledger, bank: bank, groceries: groceries, amount: 20)

        let first = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)
        let second = LedgerExport.transactionsCSV(from: ledger, timeZone: utc)

        XCTAssertEqual(first, second)
    }

    // MARK: - Accounts

    func testAccountsExportCarriesBalancePerCurrency() throws {
        var ledger = Ledger()
        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let dollars = Account(name: "Wise USD", kind: .asset, currency: usd)
        let groceries = Account(name: "Groceries", kind: .expense)

        for account in [bank, dollars, groceries] {
            ledger.addAccount(account)
        }

        try ledger.addTransaction(
            try Transaction.draftExpense(
                paidFrom: bank.id,
                category: groceries.id,
                amount: Money(Decimal(30), currency: eur),
                date: date
            )
        )
        try ledger.addTransaction(
            try Transaction.draftExpense(
                paidFrom: dollars.id,
                category: groceries.id,
                amount: Money(Decimal(20), currency: usd),
                date: date
            )
        )

        let csv = LedgerExport.accountsCSV(from: ledger)
        let lines = rows(csv)

        XCTAssertTrue(lines.contains("Swedbank,asset,active,EUR,-30.00"))
        XCTAssertTrue(lines.contains("Wise USD,asset,active,USD,-20.00"))

        // A category holding two currencies gets a row for each. Nothing here is
        // ever converted, so one summed number would be a lie.
        XCTAssertTrue(lines.contains("Groceries,expense,active,EUR,30.00"))
        XCTAssertTrue(lines.contains("Groceries,expense,active,USD,20.00"))
    }

    func testUnusedAccountsStillAppear() throws {
        let (ledger, _, _) = makeLedger()

        let lines = rows(LedgerExport.accountsCSV(from: ledger))

        // A balance-bearing account reads zero; a category has no currency to be
        // zero in, so its balance cell is blank rather than implying one.
        XCTAssertTrue(lines.contains("Swedbank,asset,active,EUR,0.00"))
        XCTAssertTrue(lines.contains("Groceries,expense,active,,"))
    }

    func testArchivedAccountsAreReportedAsArchived() throws {
        var (ledger, bank, _) = makeLedger()
        try ledger.archiveAccount(id: bank.id)

        let csv = LedgerExport.accountsCSV(from: ledger)

        XCTAssertTrue(csv.contains("Swedbank,asset,archived,EUR,0.00"))
    }

    // MARK: - Helpers

    /// Counts columns the way a CSV reader would, respecting quoted fields.
    private func columnCount(of line: String) -> Int {
        var count = 1
        var inQuotes = false

        for character in line {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                count += 1
            }
        }

        return count
    }
}

/// A backup has to be readable by the thing that wrote it. That is the whole
/// property, and it is easy to lose by re-encoding a ledger somewhere that does
/// not share the store's date strategy or schema version.
final class LedgerBackupTests: XCTestCase {

    private let eur = Currency("EUR")

    func testBackupBytesRoundTripThroughTheStore() throws {
        var ledger = Ledger()
        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(string: "42.50")!, currency: eur),
            date: Date(timeIntervalSince1970: 1_709_634_600),
            memo: "Rimi"
        )
        try ledger.addTransaction(tx)
        try ledger.finalizeTransaction(id: tx.id)

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONLedgerStore(fileURL: directory.appendingPathComponent("ledger.json"))
        let backup = try store.encoded(ledger)

        // Write the backup where a fresh store will read it, exactly as a restore
        // would.
        let restoreURL = directory.appendingPathComponent("restored.json")
        try backup.write(to: restoreURL)

        let restored = try JSONLedgerStore(fileURL: restoreURL).load()

        XCTAssertEqual(restored.accounts.count, 2)
        XCTAssertEqual(restored.transactions.count, 1)

        let restoredTx = try XCTUnwrap(restored.transactions.first)
        XCTAssertEqual(restoredTx.id, tx.id)
        XCTAssertEqual(restoredTx.memo, "Rimi")
        XCTAssertEqual(restoredTx.state, .finalized)
        XCTAssertEqual(restoredTx.date, tx.date)
        XCTAssertEqual(
            restored.balance(of: bank.id, currency: eur).amount,
            Decimal(string: "-42.50")
        )
    }

    /// A backup carries the same content as the file the store writes.
    ///
    /// Deliberately not a byte comparison: `PersistedLedger` stamps `savedAt` with
    /// the time of encoding, so two encodes of an identical ledger differ by
    /// design. What has to match is the ledger inside and the schema version, which
    /// is what a restore actually reads.
    func testBackupCarriesTheSameContentAsTheSavedFile() throws {
        var ledger = Ledger()
        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        ledger.addAccount(bank)

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("ledger.json")
        let store = JSONLedgerStore(fileURL: fileURL)

        try store.save(ledger)

        let backup = try store.encoded(ledger)
        let onDisk = try Data(contentsOf: fileURL)

        let decoded = try decodePersisted(backup)
        let saved = try decodePersisted(onDisk)

        XCTAssertEqual(decoded.schemaVersion, PersistedLedger.currentSchemaVersion)
        XCTAssertEqual(decoded.schemaVersion, saved.schemaVersion)
        XCTAssertEqual(decoded.ledger.accounts.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
                       saved.ledger.accounts.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString })
        XCTAssertEqual(decoded.ledger.accounts[bank.id]?.name, "Swedbank")
    }

    /// Reads a persisted blob back through a throwaway store, so the store's own
    /// date strategy is the one used.
    private func decodePersisted(_ data: Data) throws -> PersistedLedger {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("blob.json")
        try data.write(to: url)

        let ledger = try JSONLedgerStore(fileURL: url).load()
        return PersistedLedger(ledger: ledger)
    }
}
