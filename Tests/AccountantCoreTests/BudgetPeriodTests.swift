import XCTest
@testable import AccountantCore

final class BudgetPeriodTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Normalisation

    func testMonthAboveTwelveRollsIntoNextYear() {
        XCTAssertEqual(BudgetPeriod(year: 2026, month: 13), BudgetPeriod(year: 2027, month: 1))
        XCTAssertEqual(BudgetPeriod(year: 2026, month: 24), BudgetPeriod(year: 2027, month: 12))
        XCTAssertEqual(BudgetPeriod(year: 2026, month: 25), BudgetPeriod(year: 2028, month: 1))
    }

    func testMonthBelowOneRollsIntoPreviousYear() {
        XCTAssertEqual(BudgetPeriod(year: 2026, month: 0), BudgetPeriod(year: 2025, month: 12))
        XCTAssertEqual(BudgetPeriod(year: 2026, month: -1), BudgetPeriod(year: 2025, month: 11))
        XCTAssertEqual(BudgetPeriod(year: 2026, month: -11), BudgetPeriod(year: 2025, month: 1))
        XCTAssertEqual(BudgetPeriod(year: 2026, month: -12), BudgetPeriod(year: 2024, month: 12))
    }

    func testNextAndPreviousCrossYearBoundaries() {
        XCTAssertEqual(BudgetPeriod(year: 2026, month: 12).next, BudgetPeriod(year: 2027, month: 1))
        XCTAssertEqual(BudgetPeriod(year: 2026, month: 1).previous, BudgetPeriod(year: 2025, month: 12))
    }

    func testRoundTripThroughNextAndPreviousIsIdentity() {
        let period = BudgetPeriod(year: 2026, month: 1)
        XCTAssertEqual(period.next.previous, period)
        XCTAssertEqual(period.previous.next, period)
    }

    // MARK: - Ordering

    func testOrderingIsChronological() {
        XCTAssertLessThan(BudgetPeriod(year: 2026, month: 1), BudgetPeriod(year: 2026, month: 2))
        XCTAssertLessThan(BudgetPeriod(year: 2026, month: 12), BudgetPeriod(year: 2027, month: 1))
        XCTAssertGreaterThan(BudgetPeriod(year: 2027, month: 1), BudgetPeriod(year: 2026, month: 12))
    }

    // MARK: - Intervals

    func testIntervalCoversTheWholeMonthAndExcludesTheNext() throws {
        let august = BudgetPeriod(year: 2026, month: 8)
        let interval = try XCTUnwrap(august.dateInterval(calendar: utc))

        let firstMoment = try XCTUnwrap(
            utc.date(from: DateComponents(year: 2026, month: 8, day: 1))
        )
        let lastDay = try XCTUnwrap(
            utc.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 23, minute: 59))
        )
        let nextMonth = try XCTUnwrap(
            utc.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )

        XCTAssertEqual(interval.start, firstMoment)
        XCTAssertEqual(interval.end, nextMonth)

        XCTAssertTrue(august.contains(firstMoment, calendar: utc))
        XCTAssertTrue(august.contains(lastDay, calendar: utc))

        // Half-open: the first instant of September is not August.
        XCTAssertFalse(august.contains(nextMonth, calendar: utc))
    }

    func testFebruaryInALeapYearIsTwentyNineDays() throws {
        let february = BudgetPeriod(year: 2028, month: 2)
        let interval = try XCTUnwrap(february.dateInterval(calendar: utc))

        let days = utc.dateComponents([.day], from: interval.start, to: interval.end).day
        XCTAssertEqual(days, 29)
    }

    func testDecemberIntervalRollsIntoJanuary() throws {
        let december = BudgetPeriod(year: 2026, month: 12)
        let interval = try XCTUnwrap(december.dateInterval(calendar: utc))

        let january = try XCTUnwrap(
            utc.date(from: DateComponents(year: 2027, month: 1, day: 1))
        )
        XCTAssertEqual(interval.end, january)
    }

    func testContainingDerivesThePeriodFromADate() throws {
        let date = try XCTUnwrap(
            utc.date(from: DateComponents(year: 2026, month: 8, day: 17))
        )

        XCTAssertEqual(
            BudgetPeriod.containing(date, calendar: utc),
            BudgetPeriod(year: 2026, month: 8)
        )
    }

    // MARK: - Persistence

    func testPeriodRoundTripsThroughCoding() throws {
        let period = BudgetPeriod(year: 2026, month: 8)
        let data = try JSONEncoder().encode(period)

        XCTAssertEqual(try JSONDecoder().decode(BudgetPeriod.self, from: data), period)
    }
}
