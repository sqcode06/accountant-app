import XCTest
@testable import AccountantCore

/// Parses the shapes real Estonian bank exports actually have.
///
/// The fixtures below are the structure of genuine Swedbank, LHV and Revolut
/// exports with the values replaced. Structure is the part that breaks importers:
/// delimiter, quoting, date format, decimal separator, where the sign lives, and
/// which rows are not transactions at all.
final class StatementFormatTests: XCTestCase {

    private let eur = Currency("EUR")

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ line: BankLine) -> DateComponents {
        Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day],
            from: line.date
        )
    }

    // MARK: - Swedbank

    /// Semicolons, every field quoted, a trailing delimiter, decimal comma,
    /// dd.MM.yyyy dates, direction in a D/K column, and structural rows mixed in.
    private static let swedbank = """
    "Client account";"Row type";"Date";"Beneficiary/Payer";"Details";"Amount";"Currency";"Debit/Credit";"Transfer reference";"Transaction type";"Reference number";"Document number";
    "EE392200229999999999";"10";"01.08.2026";"";"Opening balance";"0,00";"EUR";"K";"";"AS";"";"";
    "EE392200229999999999";"20";"05.08.2026";"RIMI EESTI";"Card payment";"12,34";"EUR";"D";"REF-1";"MK";"";"";
    "EE392200229999999999";"20";"06.08.2026";"SALARY";"Wages";"1 500,00";"EUR";"K";"REF-2";"MK";"";"";
    "EE392200229999999999";"82";"11.08.2026";"";"Turnover";"12,34";"EUR";"D";"";"K2";"";"";
    "EE392200229999999999";"82";"11.08.2026";"";"Turnover";"1500,00";"EUR";"K";"";"K2";"";"";
    """

    func testSwedbankSignComesFromTheDebitCreditColumn() throws {
        let result = try StatementFormat.swedbank.makeParser(source: "Swedbank").parseLines(Self.swedbank)

        XCTAssertFalse(result.hasRowErrors, "\(result.rowErrors)")
        XCTAssertEqual(result.lines.count, 2)

        // Amounts in the file are all positive; only the D/K column says which way.
        // Reading them at face value would turn every expense into income and the
        // transaction would still balance, so nothing downstream would notice.
        XCTAssertEqual(result.lines[0].amount, Decimal(string: "-12.34"))
        XCTAssertEqual(result.lines[1].amount, Decimal(string: "1500.00"))
    }

    func testSwedbankStructuralRowsAreNotImported() throws {
        let result = try StatementFormat.swedbank.makeParser(source: "Swedbank").parseLines(Self.swedbank)

        // Row type 10 is an opening balance and 82 is a turnover total written
        // twice, once each way. Importing them invents a transaction and
        // double-counts the month.
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertFalse(result.lines.contains { $0.description.contains("Opening balance") })
        XCTAssertFalse(result.lines.contains { $0.description.contains("Turnover") })
    }

    func testSwedbankDecimalCommaAndSpaceGrouping() throws {
        let result = try StatementFormat.swedbank.makeParser(source: "Swedbank").parseLines(Self.swedbank)

        // "1 500,00" — space grouping and a decimal comma in one value.
        XCTAssertEqual(result.lines[1].amount, Decimal(1500))
    }

    func testSwedbankDatesAndReferences() throws {
        let result = try StatementFormat.swedbank.makeParser(source: "Swedbank").parseLines(Self.swedbank)

        XCTAssertEqual(day(result.lines[0]).day, 5)
        XCTAssertEqual(day(result.lines[0]).month, 8)
        XCTAssertEqual(result.lines[0].externalID, "REF-1")
    }

    // MARK: - LHV

    private static let lhv = """
    Customer account no,Date,Sender/receiver account,Sender/receiver name,Debit/Credit (D/C),Amount,Reference number,Archiving code,Description,Currency,Personal code or register code
    EE667700779999999999,2026-07-22,LT103250099999999999,SOMEONE,C,22.46,REF-A,ARCH-1,Sent from Revolut,EUR,123
    EE667700779999999999,2026-07-23,EE562200229999999999,BOLT.EU,D,27.55,REF-B,ARCH-2,Ride,EUR,456
    """

    func testLHVSignComesFromItsOwnColumn() throws {
        let result = try StatementFormat.lhv.makeParser(source: "LHV").parseLines(Self.lhv)

        XCTAssertFalse(result.hasRowErrors, "\(result.rowErrors)")
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].amount, Decimal(string: "22.46"), "C is money in")
        XCTAssertEqual(result.lines[1].amount, Decimal(string: "-27.55"), "D is money out")
    }

    func testLHVToleratesRowsMissingTrailingFields() throws {
        // Observed in real exports: trailing empty columns simply absent.
        let ragged = """
        Customer account no,Date,Sender/receiver account,Sender/receiver name,Debit/Credit (D/C),Amount,Reference number,Archiving code,Description,Currency,Personal code or register code
        EE667700779999999999,2026-07-22,LT10,SOMEONE,D,10.00,REF-A,ARCH,Coffee,EUR
        """

        let result = try StatementFormat.lhv.makeParser(source: "LHV").parseLines(ragged)

        XCTAssertFalse(result.hasRowErrors, "\(result.rowErrors)")
        XCTAssertEqual(result.lines.first?.amount, Decimal(string: "-10.00"))
    }

    func testAShiftedRowStillFailsRatherThanImportingNonsense() throws {
        // Padding tolerates missing *trailing* fields. A row shifted by a missing
        // middle field lands a name where the date belongs, and must not import.
        let shifted = """
        Customer account no,Date,Sender/receiver account,Sender/receiver name,Debit/Credit (D/C),Amount,Reference number,Archiving code,Description,Currency,Personal code or register code
        EE667700779999999999,SOMEONE,D,10.00,REF-A,ARCH,Coffee,EUR
        """

        let result = try StatementFormat.lhv.makeParser(source: "LHV").parseLines(shifted)

        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertEqual(result.rowErrors.count, 1)
    }

    // MARK: - Revolut

    private static let revolut = """
    Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
    Transfer,Current,2026-07-02 19:17:32,2026-07-02 19:17:33,Transfer in,45.00,0.00,EUR,COMPLETED,60.00
    Card Payment,Current,2026-07-07 16:27:53,2026-07-08 06:57:57,EDEKA,-3.00,0.50,EUR,COMPLETED,132.00
    Card Payment,Current,2026-07-09 10:00:00,2026-07-09 10:00:01,PENDING SHOP,-9.99,0.00,EUR,PENDING,122.01
    Card Payment,Current,2026-07-10 10:00:00,2026-07-10 10:00:01,REVERSED,-5.00,0.00,EUR,REVERTED,122.01
    """

    func testRevolutKeepsOnlyCompletedRows() throws {
        let result = try StatementFormat.revolut.makeParser(source: "Revolut").parseLines(Self.revolut)

        XCTAssertFalse(result.hasRowErrors, "\(result.rowErrors)")

        // Pending and reverted entries are not facts yet.
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertFalse(result.lines.contains { $0.description.contains("PENDING") })
        XCTAssertFalse(result.lines.contains { $0.description.contains("REVERSED") })
    }

    func testRevolutUsesTheSignedAmountAndParsesTimestamps() throws {
        let result = try StatementFormat.revolut.makeParser(source: "Revolut").parseLines(Self.revolut)

        XCTAssertEqual(result.lines[0].amount, Decimal(45))
        XCTAssertEqual(result.lines[1].amount, Decimal(-3))
        XCTAssertEqual(day(result.lines[1]).day, 8, "uses Completed Date, not Started Date")
    }

    func testRevolutFeesAreCarriedAndNormalisedPositive() throws {
        let result = try StatementFormat.revolut.makeParser(source: "Revolut").parseLines(Self.revolut)

        XCTAssertNil(result.lines[0].fee, "a zero fee is no fee")
        XCTAssertFalse(result.lines[0].hasFee)

        XCTAssertEqual(result.lines[1].fee, Decimal(string: "0.50"))
        XCTAssertTrue(result.lines[1].hasFee)
    }

    func testRevolutHasNoExternalID() throws {
        let result = try StatementFormat.revolut.makeParser(source: "Revolut").parseLines(Self.revolut)

        // Nothing in the export is stable enough to key duplicates on. The import
        // preview already warns per line when this happens.
        XCTAssertNil(result.lines[0].externalID)
    }

    // MARK: - Cross-format

    func testAMissingSignColumnFailsTheWholeFileNotEachRow() throws {
        // Every row would come out with the wrong direction, so this is a
        // structural failure rather than a row-level one.
        let missing = """
        Client account;Row type;Date;Details;Amount;Currency
        EE39;20;05.08.2026;Card payment;12,34;EUR
        """

        XCTAssertThrowsError(
            try StatementFormat.swedbank.makeParser(source: "Swedbank").parseLines(missing)
        ) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .missingRequiredColumn("Debit/Credit")
            )
        }
    }

    func testAnUnrecognisedIndicatorIsAPerRowFailure() throws {
        let odd = """
        "Client account";"Row type";"Date";"Beneficiary/Payer";"Details";"Amount";"Currency";"Debit/Credit";"Transfer reference";"Transaction type";"Reference number";"Document number";
        "EE39";"20";"05.08.2026";"";"Fine";"1,00";"EUR";"D";"";"MK";"";"";
        "EE39";"20";"06.08.2026";"";"Odd";"1,00";"EUR";"?";"";"MK";"";"";
        """

        let result = try StatementFormat.swedbank.makeParser(source: "Swedbank").parseLines(odd)

        // One good row survives; the ambiguous one is named rather than guessed at.
        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.rowErrors.count, 1)
    }

    func testEveryPresetIsRegisteredAndLookupFallsBack() {
        XCTAssertEqual(Set(StatementFormat.all.map(\.id)).count, StatementFormat.all.count)
        XCTAssertEqual(StatementFormat.format(id: "swedbank").id, "swedbank")
        XCTAssertEqual(StatementFormat.format(id: "nope").id, StatementFormat.generic.id)
    }
}
