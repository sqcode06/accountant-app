import XCTest
@testable import AccountantCore

/// A fee is money that left the account and has to land somewhere.
final class ImportFeeTests: XCTestCase {

    private let eur = Currency("EUR")

    private struct Fixture {
        var ledger: Ledger
        let bank: Account
        let uncategorised: Account
        let fees: Account
    }

    private func makeFixture() -> Fixture {
        var ledger = Ledger()

        let bank = Account(name: "Revolut", kind: .asset, currency: eur)
        let uncategorised = Account(name: "Uncategorised", kind: .expense)
        let fees = Account(name: "Bank fees", kind: .expense)

        for account in [bank, uncategorised, fees] {
            ledger.addAccount(account)
        }

        return Fixture(ledger: ledger, bank: bank, uncategorised: uncategorised, fees: fees)
    }

    private func pipeline(_ fixture: Fixture, withFeeAccount: Bool = true) -> ImportPipeline {
        ImportPipeline(
            source: "Revolut",
            statementAccountID: fixture.bank.id,
            defaultCounterpartyAccountID: fixture.uncategorised.id,
            feeAccountID: withFeeAccount ? fixture.fees.id : nil
        )
    }

    private func line(amount: Decimal, fee: Decimal?) -> BankLine {
        BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: amount,
            currency: eur,
            description: "EDEKA",
            externalID: "R-1",
            fee: fee
        )
    }

    // MARK: - Shape

    func testAFeeBecomesAThirdPostingOnTheSameTransaction() throws {
        let fixture = makeFixture()

        let draft = try pipeline(fixture).makeDraft(
            from: line(amount: Decimal(-3), fee: Decimal(string: "0.50"))
        )

        // One statement line is one transaction. Two transactions would leave one
        // of them permanently unmatched during reconciliation.
        XCTAssertEqual(draft.postings.count, 3)
        try draft.validate()
    }

    func testTheAccountLosesTheAmountPlusTheFee() throws {
        let fixture = makeFixture()

        let draft = try pipeline(fixture).makeDraft(
            from: line(amount: Decimal(-3), fee: Decimal(string: "0.50"))
        )

        func amount(_ account: Account) -> Decimal? {
            draft.postings.first { $0.accountID == account.id }?.money.amount
        }

        XCTAssertEqual(amount(fixture.bank), Decimal(string: "-3.50"))
        XCTAssertEqual(amount(fixture.uncategorised), Decimal(3))
        XCTAssertEqual(amount(fixture.fees), Decimal(string: "0.50"))
    }

    func testAFeeOnMoneyComingInReducesWhatArrives() throws {
        let fixture = makeFixture()

        let draft = try pipeline(fixture).makeDraft(
            from: line(amount: Decimal(45), fee: Decimal(string: "0.50"))
        )

        func amount(_ account: Account) -> Decimal? {
            draft.postings.first { $0.accountID == account.id }?.money.amount
        }

        // 45 arrives, 0.50 is charged, so the balance moves by 44.50.
        XCTAssertEqual(amount(fixture.bank), Decimal(string: "44.50"))
        XCTAssertEqual(amount(fixture.fees), Decimal(string: "0.50"))
        try draft.validate()
    }

    func testNoFeeMeansTwoPostingsAsBefore() throws {
        let fixture = makeFixture()

        let draft = try pipeline(fixture).makeDraft(from: line(amount: Decimal(-3), fee: nil))
        XCTAssertEqual(draft.postings.count, 2)

        let zeroFee = try pipeline(fixture).makeDraft(from: line(amount: Decimal(-3), fee: .zero))
        XCTAssertEqual(zeroFee.postings.count, 2, "a zero fee is no fee")
    }

    // MARK: - Missing fee account

    func testAFeeWithNowhereToGoFailsThatLineVisibly() throws {
        var fixture = makeFixture()

        let preview = pipeline(fixture, withFeeAccount: false).previewImport(
            lines: [line(amount: Decimal(-3), fee: Decimal(string: "0.50"))],
            into: fixture.ledger
        )

        guard case let .failed(_, error) = preview.outcomes.first else {
            return XCTFail("Expected the line to fail, got \(String(describing: preview.outcomes.first))")
        }

        XCTAssertEqual(error, .feeAccountMissing)

        // And nothing is imported, so the balance cannot end up short by the fee.
        let report = try pipeline(fixture, withFeeAccount: false)
            .applyImportPreview(preview, to: &fixture.ledger)

        XCTAssertEqual(report.insertedTransactions, 0)
    }

    func testLinesWithoutFeesStillImportWhenNoFeeAccountIsSet() throws {
        var fixture = makeFixture()

        let preview = pipeline(fixture, withFeeAccount: false).previewImport(
            lines: [line(amount: Decimal(-3), fee: nil)],
            into: fixture.ledger
        )

        let report = try pipeline(fixture, withFeeAccount: false)
            .applyImportPreview(preview, to: &fixture.ledger)

        XCTAssertEqual(report.insertedTransactions, 1)
    }

    // MARK: - End to end

    func testImportingARevolutStatementWithAFeeLeavesTheBalanceCorrect() throws {
        var fixture = makeFixture()
        let pipeline = pipeline(fixture)

        let preview = pipeline.previewImport(
            lines: [
                line(amount: Decimal(-3), fee: Decimal(string: "0.50")),
                BankLine(
                    date: Date(timeIntervalSince1970: 200),
                    amount: Decimal(45),
                    currency: eur,
                    description: "Transfer in",
                    externalID: "R-2",
                    fee: nil
                )
            ],
            into: fixture.ledger
        )

        let report = try pipeline.applyImportPreview(preview, to: &fixture.ledger)
        XCTAssertEqual(report.insertedTransactions, 2)

        // -3.50 out, +45 in.
        XCTAssertEqual(
            fixture.ledger.balance(of: fixture.bank.id, currency: eur).amount,
            Decimal(string: "41.50")
        )
        XCTAssertEqual(
            fixture.ledger.balance(of: fixture.fees.id, currency: eur).amount,
            Decimal(string: "0.50")
        )
    }
}
