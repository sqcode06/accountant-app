import XCTest
@testable import AccountantCore

final class MergeAccountTests: XCTestCase {
    func testMergeAccountKindMismatchCanThrowDedicatedError() throws {
        let id = AccountID(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)
        var local = Ledger()
        var incoming = Ledger()

        let localAccount = Account(id: id, name: "Bucket", kind: .asset)
        let incomingAccount = Account(id: id, name: "Bucket", kind: .expense)

        local.addAccount(localAccount)
        incoming.addAccount(incomingAccount)

        var options = LedgerMergeOptions()
        options.accountConflictResolution = .error

        XCTAssertThrowsError(try local.mergeFinalized(from: incoming, options: options)) { error in
            guard case LedgerMergeError.accountMismatch(let accountID, let localValue, let incomingValue) = error else {
                return XCTFail("Expected accountMismatch, got: \(error)")
            }

            XCTAssertEqual(accountID, id)
            XCTAssertEqual(localValue.kind, .asset)
            XCTAssertEqual(incomingValue.kind, .expense)
        }

        XCTAssertEqual(local.accounts[id]?.kind, .asset)
    }

    func testMergeAccountStatusMismatchCanKeepLocalAndReportConflict() throws {
        let id = AccountID(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!)
        var local = Ledger()
        var incoming = Ledger()

        let localAccount = Account(id: id, name: "Old Card", kind: .liability, status: .active)
        let incomingAccount = Account(id: id, name: "Old Card", kind: .liability, status: .archived)

        local.addAccount(localAccount)
        incoming.addAccount(incomingAccount)

        var options = LedgerMergeOptions()
        options.accountConflictResolution = .keepLocal

        let report = try local.mergeFinalized(from: incoming, options: options)

        XCTAssertEqual(report.updatedAccounts, 0)
        XCTAssertEqual(local.accounts[id]?.status, .active)
        XCTAssertTrue(report.conflicts.contains(.accountMismatch(accountID: id, local: localAccount, incoming: incomingAccount)))
    }

    func testMergeAccountStatusMismatchCanPreferIncoming() throws {
        let id = AccountID(UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!)
        var local = Ledger()
        var incoming = Ledger()

        let localAccount = Account(id: id, name: "Old Card", kind: .liability, status: .active)
        let incomingAccount = Account(id: id, name: "Old Card", kind: .liability, status: .archived)

        local.addAccount(localAccount)
        incoming.addAccount(incomingAccount)

        var options = LedgerMergeOptions()
        options.accountConflictResolution = .preferIncoming

        let report = try local.mergeFinalized(from: incoming, options: options)

        XCTAssertEqual(report.updatedAccounts, 1)
        XCTAssertEqual(local.accounts[id]?.status, .archived)
    }
}
