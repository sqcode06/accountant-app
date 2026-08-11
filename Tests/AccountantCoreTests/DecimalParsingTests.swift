import XCTest
@testable import AccountantCore

/// Money written the way banks actually write it.
///
/// The failure this guards against is not a crash — it is a string that parses
/// into the wrong number and lands in the ledger looking perfectly reasonable.
final class DecimalParsingTests: XCTestCase {

    private func parse(_ text: String) -> Decimal? {
        DecimalParsing.decimal(from: text)
    }

    // MARK: - Plain

    func testPlainNumbers() {
        XCTAssertEqual(parse("42"), Decimal(42))
        XCTAssertEqual(parse("42.50"), Decimal(string: "42.50"))
        XCTAssertEqual(parse("-42.50"), Decimal(string: "-42.50"))
        XCTAssertEqual(parse("0"), Decimal(0))
        XCTAssertEqual(parse("  42.50  "), Decimal(string: "42.50"))
    }

    // MARK: - Decimal comma

    func testCommaAsDecimalSeparator() {
        XCTAssertEqual(parse("42,50"), Decimal(string: "42.50"))
        XCTAssertEqual(parse("-42,50"), Decimal(string: "-42.50"))
        XCTAssertEqual(parse("0,05"), Decimal(string: "0.05"))
    }

    // MARK: - Grouping

    func testBothSeparatorConventionsResolveToTheSameNumber() {
        // The old implementation replaced every comma with a dot, which turned
        // 1.234,56 into 1.234.56 and failed outright.
        XCTAssertEqual(parse("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(parse("1.234.567,89"), Decimal(string: "1234567.89"))
        XCTAssertEqual(parse("1,234,567.89"), Decimal(string: "1234567.89"))
    }

    func testSpaceAndApostropheGrouping() {
        XCTAssertEqual(parse("1 234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(parse("1\u{00A0}234,56"), Decimal(string: "1234.56"), "non-breaking space")
        XCTAssertEqual(parse("1'234.56"), Decimal(string: "1234.56"), "Swiss")
    }

    func testGroupingWithoutADecimalPart() {
        XCTAssertEqual(parse("1.234"), Decimal(1234), "dot grouping, no decimals")
        XCTAssertEqual(parse("1,234"), Decimal(1234), "comma grouping, no decimals")
        XCTAssertEqual(parse("1.234.567"), Decimal(1234567))
    }

    /// The genuinely ambiguous case, documented rather than left to chance.
    ///
    /// "1,234" is far more often one thousand two hundred and thirty-four than it
    /// is 1.234, so three trailing digits are read as grouping. Any other count is
    /// unambiguous and read as a decimal.
    func testThreeTrailingDigitsAfterASingleCommaReadAsGrouping() {
        XCTAssertEqual(parse("1,234"), Decimal(1234))
        XCTAssertEqual(parse("1,23"), Decimal(string: "1.23"))
        XCTAssertEqual(parse("1,2"), Decimal(string: "1.2"))
        XCTAssertEqual(parse("1,2345"), Decimal(string: "1.2345"))
    }

    // MARK: - Signs

    func testAccountingParenthesesAreNegative() {
        XCTAssertEqual(parse("(42.50)"), Decimal(string: "-42.50"))
        XCTAssertEqual(parse("(1.234,56)"), Decimal(string: "-1234.56"))
        XCTAssertEqual(parse("( 42.50 )"), Decimal(string: "-42.50"))
    }

    func testTrailingMinusIsNegative() {
        XCTAssertEqual(parse("42.50-"), Decimal(string: "-42.50"))
        XCTAssertEqual(parse("1 234,56-"), Decimal(string: "-1234.56"))
    }

    // MARK: - Rejection

    func testNonNumbersAreRejected() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("   "))
        XCTAssertNil(parse("abc"))
        XCTAssertNil(parse("EUR"))
        XCTAssertNil(parse("--"))
    }

    // MARK: - Precision

    func testNoBinaryFloatingPointDrift() {
        // Decimal all the way through; 0.1 + 0.2 must be exactly 0.3.
        let a = try? XCTUnwrap(parse("0.1"))
        let b = try? XCTUnwrap(parse("0.2"))

        XCTAssertEqual((a ?? 0) + (b ?? 0), Decimal(string: "0.3"))
    }

    func testLargeAmountsKeepTheirCents() {
        XCTAssertEqual(parse("1 234 567,89"), Decimal(string: "1234567.89"))
        XCTAssertEqual(parse("99999999.99"), Decimal(string: "99999999.99"))
    }
}
