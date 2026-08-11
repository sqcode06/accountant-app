import XCTest
@testable import AccountantCore

/// Covers the failure that destroys data.
///
/// A store that cannot decode its file used to throw, callers read that as "no
/// data yet", and the next save wrote an empty document over the real one. These
/// tests pin the distinction between "nothing here yet" and "something here I
/// cannot read", and that the second case never loses bytes.
final class LedgerLoadOutcomeTests: XCTestCase {

    private let eur = Currency("EUR")
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-outcome-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL {
        directory.appendingPathComponent("ledger.json")
    }

    private func makeLedger() -> Ledger {
        var ledger = Ledger()
        ledger.addAccount(Account(name: "Swedbank", kind: .asset, currency: eur))
        return ledger
    }

    private func quarantinedFiles() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("unreadable") }
            .sorted()
    }

    // MARK: - The ordinary cases

    func testAbsentFileReadsAsEmptyRatherThanDamaged() throws {
        let store = JSONLedgerStore(fileURL: fileURL)

        guard case .empty = store.loadOutcome() else {
            return XCTFail("A first run must be .empty, not .unreadable — otherwise the app locks itself on launch")
        }

        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }

    func testValidFileLoads() throws {
        let store = JSONLedgerStore(fileURL: fileURL)
        try store.save(makeLedger())

        guard case let .loaded(ledger) = store.loadOutcome() else {
            return XCTFail("Expected .loaded")
        }

        XCTAssertEqual(ledger.accounts.count, 1)
        XCTAssertTrue(try quarantinedFiles().isEmpty)
    }

    // MARK: - The dangerous case

    func testUnreadableFileIsQuarantinedAndReportedAsSuch() throws {
        try Data("this is not json".utf8).write(to: fileURL)

        let store = JSONLedgerStore(fileURL: fileURL)

        guard case let .unreadable(record) = store.loadOutcome() else {
            return XCTFail("A corrupt file must never read as .empty")
        }

        XCTAssertTrue(record.didMove)
        XCTAssertEqual(record.originalURL, fileURL)
        XCTAssertFalse(record.reason.isEmpty)
        XCTAssertEqual(try quarantinedFiles().count, 1)
    }

    func testQuarantinePreservesTheOriginalBytesExactly() throws {
        let original = Data("this is not json, but it is the user's only copy".utf8)
        try original.write(to: fileURL)

        let store = JSONLedgerStore(fileURL: fileURL)

        guard case let .unreadable(record) = store.loadOutcome() else {
            return XCTFail("Expected .unreadable")
        }

        // The entire point: nothing is lost.
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)

        // And the original path is now clear, so a later save cannot destroy it.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAFutureSchemaIsTreatedAsUnreadableNotEmpty() throws {
        // A ledger written by a newer build must not be silently replaced by an
        // empty one from an older build.
        let json = """
        { "schemaVersion": 9999, "savedAt": "0", "ledger": { "accounts": [], "transactions": [] } }
        """
        try Data(json.utf8).write(to: fileURL)

        let store = JSONLedgerStore(fileURL: fileURL)

        guard case .unreadable = store.loadOutcome() else {
            return XCTFail("An unsupported schema version must quarantine, not read as empty")
        }
    }

    func testQuarantiningTwiceDoesNotCollide() throws {
        let store = JSONLedgerStore(fileURL: fileURL)

        try Data("garbage one".utf8).write(to: fileURL)
        guard case let .unreadable(first) = store.loadOutcome() else {
            return XCTFail("Expected .unreadable")
        }

        // Same second, same generated name — the counter has to save us.
        try Data("garbage two".utf8).write(to: fileURL)
        guard case let .unreadable(second) = store.loadOutcome() else {
            return XCTFail("Expected .unreadable")
        }

        XCTAssertNotEqual(first.quarantinedURL, second.quarantinedURL)
        XCTAssertEqual(try quarantinedFiles().count, 2)

        XCTAssertEqual(try Data(contentsOf: first.quarantinedURL), Data("garbage one".utf8))
        XCTAssertEqual(try Data(contentsOf: second.quarantinedURL), Data("garbage two".utf8))
    }

    // MARK: - Recovery

    func testStoreIsUsableAgainAfterQuarantine() throws {
        try Data("not json".utf8).write(to: fileURL)

        let store = JSONLedgerStore(fileURL: fileURL)
        _ = store.loadOutcome()

        // "Start fresh" must work: the path is clear and saving succeeds.
        try store.save(makeLedger())

        guard case let .loaded(ledger) = store.loadOutcome() else {
            return XCTFail("Expected .loaded after starting fresh")
        }

        XCTAssertEqual(ledger.accounts.count, 1)
        XCTAssertEqual(try quarantinedFiles().count, 1, "The quarantined copy must survive starting fresh")
    }
}
