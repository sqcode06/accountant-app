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

    private var recoveryURL: URL {
        directory.appendingPathComponent("ledger.recovery.json")
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
        try Data("garbage one".utf8).write(to: fileURL)
        let first = FileQuarantine.move(fileURL, reason: "first")

        // Same second, same generated name — the counter has to save us. Store
        // recovery itself now remains locked after the first failure, so this
        // exercises the intentional low-level quarantine operation directly.
        try Data("garbage two".utf8).write(to: fileURL)
        let second = FileQuarantine.move(fileURL, reason: "second")

        XCTAssertNotEqual(first.quarantinedURL, second.quarantinedURL)
        XCTAssertEqual(try quarantinedFiles().count, 2)

        XCTAssertEqual(try Data(contentsOf: first.quarantinedURL), Data("garbage one".utf8))
        XCTAssertEqual(try Data(contentsOf: second.quarantinedURL), Data("garbage two".utf8))
    }

    // MARK: - Recovery

    func testNewStoreInstanceRemainsUnreadableAfterOriginalWasMoved() throws {
        try Data("not json".utf8).write(to: fileURL)
        _ = JSONLedgerStore(fileURL: fileURL).loadOutcome()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        guard case .unreadable = JSONLedgerStore(fileURL: fileURL).loadOutcome() else {
            return XCTFail("A relaunch must retain unresolved recovery state")
        }
    }

    func testOrdinarySaveIsDeniedWhileRecoveryIsUnresolved() throws {
        try Data("not json".utf8).write(to: fileURL)
        let store = JSONLedgerStore(fileURL: fileURL)
        _ = store.loadOutcome()

        XCTAssertThrowsError(try store.save(makeLedger())) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .recoveryUnresolved)
        }
    }

    func testReplacementStaysUnreadableUntilRecoveryCompletesAndPreservesQuarantine() throws {
        let original = Data("the only old copy".utf8)
        try original.write(to: fileURL)
        let store = JSONLedgerStore(fileURL: fileURL)

        guard case let .unreadable(record) = store.loadOutcome() else {
            return XCTFail("Expected unreadable")
        }
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)

        try store.replaceForRecovery(makeLedger())
        guard case .unreadable = JSONLedgerStore(fileURL: fileURL).loadOutcome() else {
            return XCTFail("Replacement must not unlock one store before all stores are ready")
        }

        try store.completeRecovery()
        guard case let .loaded(ledger) = JSONLedgerStore(fileURL: fileURL).loadOutcome() else {
            return XCTFail("Expected the validated replacement after completion")
        }

        XCTAssertEqual(ledger.accounts.count, 1)
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
    }

    func testLegacyQuarantineIsDetectedThenDoesNotRelockAfterCompletion() throws {
        let legacyURL = directory.appendingPathComponent("ledger.unreadable-20260811-172400.json")
        let original = Data("legacy damaged bytes".utf8)
        try original.write(to: legacyURL)

        let store = JSONLedgerStore(fileURL: fileURL)
        guard case let .unreadable(record) = store.loadOutcome() else {
            return XCTFail("Legacy quarantine must not look like a first run")
        }
        XCTAssertEqual(record.quarantinedURL, legacyURL)

        try store.replaceForRecovery(makeLedger())
        try store.completeRecovery()
        guard case .loaded = JSONLedgerStore(fileURL: fileURL).loadOutcome() else {
            return XCTFail("A resolved sidecar must suppress stale legacy detection")
        }
        XCTAssertEqual(try Data(contentsOf: legacyURL), original)
    }

    func testMalformedRecoveryRecordFailsClosedAndDoesNotOverwriteOriginal() throws {
        let original = Data("damaged but preserved".utf8)
        try original.write(to: fileURL)
        try Data("not a recovery record".utf8).write(to: recoveryURL)

        let store = JSONLedgerStore(fileURL: fileURL)
        guard case .unreadable = store.loadOutcome() else {
            return XCTFail("Malformed recovery metadata must be treated as unresolved")
        }
        XCTAssertThrowsError(try store.save(makeLedger())) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .recoveryRecordUnreadable)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testInaccessibleRecoveryMarkerFailsClosedBeforeMovingOriginal() throws {
        let original = Data("damaged but preserved".utf8)
        try original.write(to: fileURL)
        try FileManager.default.createDirectory(at: recoveryURL, withIntermediateDirectories: false)

        let store = JSONLedgerStore(fileURL: fileURL)
        guard case .unreadable = store.loadOutcome() else {
            return XCTFail("An unusable recovery marker must fail closed")
        }
        XCTAssertThrowsError(try store.save(makeLedger()))
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testRecoveryReplacementCannotOverwriteAnUnmarkedUnreadableOriginal() throws {
        let original = Data("marker write may have failed".utf8)
        try original.write(to: fileURL)

        let store = JSONLedgerStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.replaceForRecovery(makeLedger())) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .originalNotSafelyQuarantined)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testResolvedTombstoneDoesNotPermitOverwritingANewCorruption() throws {
        try Data("first corruption".utf8).write(to: fileURL)
        let store = JSONLedgerStore(fileURL: fileURL)
        _ = store.loadOutcome()
        try store.replaceForRecovery(makeLedger())
        try store.completeRecovery()

        let newerCorruption = Data("new corruption after a completed recovery".utf8)
        try newerCorruption.write(to: fileURL)
        XCTAssertThrowsError(try store.save(makeLedger())) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .recoveryUnresolved)
        }
        XCTAssertThrowsError(try store.replaceForRecovery(makeLedger())) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .recoveryUnresolved)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), newerCorruption)

        guard case .unreadable = store.loadOutcome() else {
            return XCTFail("A later corruption must start a new unresolved recovery")
        }
    }

    func testRecoverySurvivesMovingTheContainingDirectory() throws {
        let original = Data("protect me across a directory move".utf8)
        try original.write(to: fileURL)
        _ = JSONLedgerStore(fileURL: fileURL).loadOutcome()

        let movedDirectory = directory.deletingLastPathComponent()
            .appendingPathComponent("moved-ledger-outcome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        directory = movedDirectory

        let movedStore = JSONLedgerStore(fileURL: fileURL)
        guard case let .unreadable(record) = movedStore.loadOutcome() else {
            return XCTFail("A local-name marker must remain valid after moving its directory")
        }
        XCTAssertEqual(try Data(contentsOf: record.quarantinedURL), original)
        try movedStore.replaceForRecovery(makeLedger())
        try movedStore.completeRecovery()
        guard case .loaded = movedStore.loadOutcome() else {
            return XCTFail("Moved recovery should complete normally")
        }
    }

    func testForgedOutOfDirectoryQuarantineNameFailsClosed() throws {
        let escapedURL = directory.deletingLastPathComponent().appendingPathComponent("outside.json")
        let escapedBytes = Data("must not be used as a quarantine target".utf8)
        try escapedBytes.write(to: escapedURL)
        defer { try? FileManager.default.removeItem(at: escapedURL) }

        let marker = """
        {"version":2,"state":"unresolved","relocation":"moved","originalFilename":"ledger.json","quarantinedFilename":"../outside.json","reason":"forged"}
        """
        try Data(marker.utf8).write(to: recoveryURL)

        let store = JSONLedgerStore(fileURL: fileURL)
        guard case .unreadable = store.loadOutcome() else {
            return XCTFail("An escaped quarantine path must be rejected")
        }
        XCTAssertThrowsError(try store.replaceForRecovery(makeLedger())) { error in
            XCTAssertEqual(error as? StoreRecoveryError, .recoveryRecordUnreadable)
        }
        XCTAssertEqual(try Data(contentsOf: escapedURL), escapedBytes)
    }
}
