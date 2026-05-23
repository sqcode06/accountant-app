import XCTest
import Foundation
@testable import AccountantCore

final class CSVBankLineParserTests: XCTestCase {
    func testParsesSimpleCSVWithQuotedDescriptionAndOptionalExternalID() throws {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description,external_id
2026-05-01,-12.34,EUR,"Coffee, croissant",CARD-1
2026-05-02,1000.00,eur,Salary,
"""

        let lines = try parser.parse(csv)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], BankLine(
            date: fixtureDate("2026-05-01"),
            amount: Decimal(string: "-12.34")!,
            currency: Currency("EUR"),
            description: "Coffee, croissant",
            externalID: "CARD-1"
        ))
        XCTAssertEqual(lines[1], BankLine(
            date: fixtureDate("2026-05-02"),
            amount: Decimal(1000),
            currency: Currency("EUR"),
            description: "Salary",
            externalID: nil
        ))
    }

    func testParsesCustomColumnsDelimiterAndDateFormat() throws {
        let parser = CSVBankLineParser(
            source: "LHV",
            columns: CSVBankLineParser.Columns(
                date: "Booked",
                amount: "Value",
                currency: "CCY",
                description: "Details",
                externalID: "Reference"
            ),
            delimiter: ";",
            dateFormats: ["dd.MM.yyyy"]
        )
        let csv = """
Reference;Booked;Details;CCY;Value
ABC-1;23.05.2026;Groceries;EUR;-5,25
"""

        let lines = try parser.parse(csv)

        XCTAssertEqual(lines, [
            BankLine(
                date: fixtureDate("23.05.2026", format: "dd.MM.yyyy"),
                amount: Decimal(string: "-5.25")!,
                currency: Currency("EUR"),
                description: "Groceries",
                externalID: "ABC-1"
            )
        ])
    }

    func testMissingRequiredColumnReportsStructuredError() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,currency,description,external_id
2026-05-01,EUR,Coffee,CARD-1
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(error as? BankLineParseError, .missingRequiredColumn("amount"))
        }
    }

    func testColumnCountMismatchReportsRowNumber() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description
2026-05-01,-12.34,EUR
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .rowColumnCountMismatch(row: 2, expected: 4, actual: 3)
            )
        }
    }

    func testMissingRequiredValueReportsColumnName() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description
2026-05-01,,EUR,Coffee
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .missingRequiredValue(row: 2, column: "amount")
            )
        }
    }

    func testInvalidDateReportsExpectedFormats() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description
05/01/2026,-12.34,EUR,Coffee
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .invalidDate(row: 2, column: "date", value: "05/01/2026", expectedFormats: ["yyyy-MM-dd"])
            )
        }
    }

    func testInvalidAmountReportsOriginalValue() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description
2026-05-01,not-money,EUR,Coffee
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .invalidAmount(row: 2, column: "amount", value: "not-money")
            )
        }
    }

    func testInvalidCurrencyReportsOriginalValue() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description
2026-05-01,-12.34,EURO,Coffee
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .invalidCurrency(row: 2, column: "currency", value: "EURO")
            )
        }
    }

    func testMalformedQuotedFieldReportsCSVError() {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = """
date,amount,currency,description
2026-05-01,-12.34,EUR,"Coffee
"""

        XCTAssertThrowsError(try parser.parse(csv)) { error in
            XCTAssertEqual(
                error as? BankLineParseError,
                .malformedCSV(row: 2, message: "Unterminated quoted field.")
            )
        }
    }

    func testEscapedQuotesAreParsed() throws {
        let parser = CSVBankLineParser(source: "FixtureBank")
        let csv = "date,amount,currency,description,external_id\n2026-05-01,-12.34,EUR,\"Coffee \"\"special\"\"\",CARD-1\n"

        let lines = try parser.parse(csv)

        XCTAssertEqual(lines.first?.description, "Coffee \"special\"")
    }

    func testEmptyInputThrowsEmptyInput() {
        let parser = CSVBankLineParser(source: "FixtureBank")

        XCTAssertThrowsError(try parser.parse(" \n \t ")) { error in
            XCTAssertEqual(error as? BankLineParseError, .emptyInput)
        }
    }
}

private func fixtureDate(_ value: String, format: String = "yyyy-MM-dd") -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format

    guard let date = formatter.date(from: value) else {
        fatalError("Invalid fixture date: \(value)")
    }

    return date
}
