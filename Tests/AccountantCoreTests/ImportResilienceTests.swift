import XCTest
@testable import AccountantCore

/// Covers the two ways a statement import used to fail badly:
/// one malformed row discarding the whole batch, and a foreign-currency row being
/// accepted into an account that cannot hold it.
final class ImportResilienceTests: XCTestCase {

    private let eur = Currency("EUR")
    private let usd = Currency("USD")

    // MARK: - Per-row CSV resilience

    private static let csvWithOneBadRow = """
    date,amount,currency,description,external_id
    2026-01-05,-12.50,EUR,RIMI EESTI,A-1
    05/01/2026,-8.00,EUR,BOLT FOOD,A-2
    2026-01-07,-30.00,EUR,SELVER,A-3
    """

    func testOneMalformedRowDoesNotDiscardTheBatch() throws {
        let parser = CSVBankLineParser(source: "Swedbank")
        let result = try parser.parseLines(Self.csvWithOneBadRow)

        // Two good rows survive; only the bad one is reported.
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.rowErrors.count, 1)
        XCTAssertTrue(result.hasRowErrors)

        XCTAssertEqual(result.lines.map(\.externalID), ["A-1", "A-3"])
    }

    func testRowErrorIdentifiesTheOffendingRowAndReason() throws {
        let parser = CSVBankLineParser(source: "Swedbank")
        let result = try parser.parseLines(Self.csvWithOneBadRow)

        let failure = try XCTUnwrap(result.rowErrors.first)

        // Row 3 in spreadsheet terms: header is row 1.
        XCTAssertEqual(failure.row, 3)

        guard case .invalidDate(_, _, let value, _) = failure.error else {
            return XCTFail("Expected invalidDate, got \(failure.error)")
        }
        XCTAssertEqual(value, "05/01/2026")
    }

    func testStrictParseStillThrowsOnTheFirstBadRow() throws {
        // The all-or-nothing path is preserved for callers that want it.
        let parser = CSVBankLineParser(source: "Swedbank")

        XCTAssertThrowsError(try parser.parse(Self.csvWithOneBadRow))
    }

    func testCleanInputReportsNoRowErrors() throws {
        let parser = CSVBankLineParser(source: "Swedbank")
        let result = try parser.parseLines("""
        date,amount,currency,description,external_id
        2026-01-05,-12.50,EUR,RIMI EESTI,A-1
        2026-01-07,-30.00,EUR,SELVER,A-3
        """)

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertFalse(result.hasRowErrors)
    }

    func testEveryRowBadStillReturnsStructurallyRatherThanThrowing() throws {
        let parser = CSVBankLineParser(source: "Swedbank")
        let result = try parser.parseLines("""
        date,amount,currency,description,external_id
        nope,-12.50,EUR,RIMI,A-1
        also-nope,-30.00,EUR,SELVER,A-3
        """)

        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertEqual(result.rowErrors.count, 2)
    }

    // MARK: - Structural failures still throw

    func testMissingRequiredColumnStillThrows() throws {
        // A missing column is not recoverable per row — every row would fail.
        let parser = CSVBankLineParser(source: "Swedbank")

        XCTAssertThrowsError(
            try parser.parseLines("""
            date,amount,description
            2026-01-05,-12.50,RIMI
            """)
        ) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .missingRequiredColumn("currency")
            )
        }
    }

    func testEmptyInputStillThrows() throws {
        let parser = CSVBankLineParser(source: "Swedbank")

        XCTAssertThrowsError(try parser.parseLines("   \n  ")) { error in
            XCTAssertEqual(error as? BankLineParseError, .emptyInput)
        }
    }

    // MARK: - Currency guard on import

    func testForeignCurrencyLineIsRejectedInPreviewRatherThanVanishing() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let uncategorized = Account(name: "Uncategorized", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)

        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )

        let preview = pipeline.previewImport(
            lines: [
                BankLine(
                    date: Date(timeIntervalSince1970: 100),
                    amount: Decimal(-42),
                    currency: usd,
                    description: "AMAZON US",
                    externalID: "US-1"
                )
            ],
            into: ledger
        )

        XCTAssertEqual(preview.outcomes.count, 1)

        guard case .failed(_, let error) = preview.outcomes[0] else {
            return XCTFail("Expected the USD line to fail, got \(preview.outcomes[0])")
        }

        XCTAssertEqual(
            error,
            .currencyMismatch(bank.id, expected: eur, actual: usd)
        )

        // And applying the preview must not smuggle it in.
        var target = ledger
        let report = try pipeline.applyImportPreview(preview, to: &target)
        XCTAssertEqual(report.insertedTransactions, 0)
        XCTAssertTrue(target.transactions.isEmpty)
    }

    func testMatchingCurrencyLineImportsNormally() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let uncategorized = Account(name: "Uncategorized", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)

        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )

        let preview = pipeline.previewImport(
            lines: [
                BankLine(
                    date: Date(timeIntervalSince1970: 100),
                    amount: Decimal(-42),
                    currency: eur,
                    description: "RIMI EESTI",
                    externalID: "EU-1"
                )
            ],
            into: ledger
        )

        var target = ledger
        let report = try pipeline.applyImportPreview(preview, to: &target)

        XCTAssertEqual(report.insertedTransactions, 1)
        XCTAssertEqual(target.balance(of: bank.id, currency: eur).amount, Decimal(-42))
    }

    // MARK: - End to end

    func testDirtyStatementImportsGoodRowsAndReportsTheBadOne() throws {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let uncategorized = Account(name: "Uncategorized", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)

        let parser = CSVBankLineParser(source: "Swedbank")
        let parsed = try parser.parseLines(Self.csvWithOneBadRow)

        let pipeline = ImportPipeline(
            source: "Swedbank",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )

        let preview = pipeline.previewImport(lines: parsed.lines, into: ledger)
        var target = ledger
        let report = try pipeline.applyImportPreview(preview, to: &target)

        // The user gets their two good rows instead of nothing at all...
        XCTAssertEqual(report.insertedTransactions, 2)
        XCTAssertEqual(target.balance(of: bank.id, currency: eur).amount, Decimal(-42.5))

        // ...and still learns which row needs attention.
        XCTAssertEqual(parsed.rowErrors.map(\.row), [3])
    }
}
