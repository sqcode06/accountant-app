import XCTest
@testable import AccountantCore

final class ImportPipelineTests: XCTestCase {
    func testImportCreatesBalancedDrafts() throws {
        let eur = Currency("EUR")

        var ledger = Ledger()
        let bank = Account(name: "Bank")
        let uncategorizedAccount = Account(name: "Uncategorized")
        ledger.addAccount(bank)
        ledger.addAccount(uncategorizedAccount)

        let pipeline = ImportPipeline(source: "MyBank", statementAccountID: bank.id, defaultCounterpartyAccountID: uncategorizedAccount.id)

        let lines = [
            BankLine(date: Date(timeIntervalSince1970: 10), amount: Decimal(-5), currency: eur, description: "Coffee", externalID: "X1"),
            BankLine(date: Date(timeIntervalSince1970: 20), amount: Decimal(100), currency: eur, description: "Salary", externalID: "X2"),
        ]

        let drafts = try pipeline.makeDrafts(from: lines)

        for draft in drafts {
            XCTAssertEqual(draft.state, .draft)
            try draft.validate()
            try ledger.addTransaction(draft) // should not throw
        }

        XCTAssertEqual(ledger.transactions.count, 2)
    }
}
