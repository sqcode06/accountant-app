import Foundation
import XCTest
@testable import AccountantApp

final class ReconciliationDateTests: XCTestCase {
    func testIncludesFractionalFinalSecondOfUtcDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15,
                                                       hour: 23, minute: 59, second: 59,
                                                       nanosecond: 500_000_000))!
        let nextStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!

        let result = ReconciliationDate.endOfDay(date, calendar: calendar)

        XCTAssertGreaterThanOrEqual(result, date)
        XCTAssertLessThan(result, nextStart)
    }

    func testExcludesNextMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let nextStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!

        XCTAssertLessThan(ReconciliationDate.endOfDay(date, calendar: calendar), nextStart)
    }

    func testHandlesShortDstDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tallinn")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        let nextStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30))!

        let result = ReconciliationDate.endOfDay(date, calendar: calendar)

        XCTAssertGreaterThanOrEqual(result, date)
        XCTAssertLessThan(result, nextStart)
        XCTAssertEqual(result.timeIntervalSinceReferenceDate,
                       nextStart.timeIntervalSinceReferenceDate.nextDown)
    }

    func testHandlesLongDstDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tallinn")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let nextStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!

        let result = ReconciliationDate.endOfDay(date, calendar: calendar)

        XCTAssertGreaterThanOrEqual(result, date)
        XCTAssertLessThan(result, nextStart)
        XCTAssertEqual(result.timeIntervalSinceReferenceDate,
                       nextStart.timeIntervalSinceReferenceDate.nextDown)
    }

    func testExcludesNextDayWhenDstSkipsMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        // This day began at 01:00. Adding a day to its start incorrectly ends
        // at 01:00 tomorrow, including an hour that belongs to the next statement.
        let date = calendar.date(from: DateComponents(year: 2018, month: 11, day: 4, hour: 12))!
        let nextStart = calendar.date(from: DateComponents(year: 2018, month: 11, day: 5))!
        let lastTransaction = nextStart.addingTimeInterval(-0.5)

        let result = ReconciliationDate.endOfDay(date, calendar: calendar)

        XCTAssertGreaterThanOrEqual(result, lastTransaction)
        XCTAssertLessThan(result, nextStart)
    }
}
