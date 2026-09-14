import XCTest
import Foundation
@testable import AccountantCore

final class PostingRoleTests: XCTestCase {
    private let eur = Currency("EUR")

    func testPostingWithoutRoleDecodesAsLegacyUntaggedPosting() throws {
        let posting = Posting(accountID: AccountID(), money: Money(Decimal(5), currency: eur))
        let data = try JSONEncoder().encode(posting)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("role"))
        XCTAssertNil(try JSONDecoder().decode(Posting.self, from: data).role)
    }

    func testImportedPostingRolesSurviveBackupRoundTrip() throws {
        let fixture = try makeImportedLedger()
        let backup = LedgerBackup(ledger: fixture.ledger)

        let restored = try LedgerBackupCoder.decode(LedgerBackupCoder.encode(backup))

        XCTAssertEqual(restored.ledger.transactions.first?.postings.map(\.role), [
            .statement,
            .counterparty,
            .fee
        ])
    }

    func testImportedPostingRolesSurviveLedgerSaveAndReload() throws {
        let fixture = try makeImportedLedger()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("posting-role-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONLedgerStore(fileURL: fileURL)

        try store.save(fixture.ledger)
        let restored = try store.load()

        XCTAssertEqual(restored.transactions.first?.postings.map(\.role), [
            .statement,
            .counterparty,
            .fee
        ])
    }

    private func makeImportedLedger() throws -> (ledger: Ledger, transaction: Transaction) {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .asset, currency: eur)
        let category = Account(name: "Groceries", kind: .expense)
        let fees = Account(name: "Fees", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(category)
        ledger.addAccount(fees)

        let pipeline = ImportPipeline(
            source: "Bank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: category.id,
            feeAccountID: fees.id
        )
        let transaction = try pipeline.makeDraft(from: BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-10),
            currency: eur,
            description: "Shop",
            externalID: "1",
            fee: Decimal(string: "0.25")
        ))
        try ledger.addTransaction(transaction)
        return (ledger, transaction)
    }
}
