import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

struct BudgetMonthSelectionTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int = 2026, month: Int, day: Int = 13) throws -> Date {
        try #require(utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @Test func startsInSeptemberAndCanReturnFromAnEarlierMonth() throws {
        let now = try date(month: 9)
        var months = BudgetMonthSelection(now: now, calendar: utc)
        #expect(months.selected == BudgetPeriod(year: 2026, month: 9))
        #expect(months.isCurrent)

        months.showPrevious()
        #expect(months.selected == BudgetPeriod(year: 2026, month: 8))
        #expect(months.canMoveForward)

        // A redraw or a tab/foreground change must not undo deliberate browsing.
        months.refresh(now: now, calendar: utc)
        #expect(months.selected == BudgetPeriod(year: 2026, month: 8))
        months.showNext()
        #expect(months.selected == BudgetPeriod(year: 2026, month: 9))

        months.showNext()
        #expect(months.isCurrent)
        #expect(!months.canMoveForward)
    }

    @Test func currentMonthShortcutReturnsFromSeveralMonthsBack() throws {
        var months = BudgetMonthSelection(now: try date(month: 9), calendar: utc)
        for _ in 0..<10 { months.showPrevious() }
        #expect(months.selected == BudgetPeriod(year: 2025, month: 11))

        months.showCurrent()
        #expect(months.selected == BudgetPeriod(year: 2026, month: 9))
        #expect(months.isCurrent)
    }

    @Test func currentMonthFollowsRolloverIncludingANewYear() throws {
        var months = BudgetMonthSelection(now: try date(month: 8, day: 31), calendar: utc)
        months.refresh(now: try date(month: 9, day: 1), calendar: utc)
        #expect(months.selected == BudgetPeriod(year: 2026, month: 9))
        #expect(months.isCurrent)

        months.refresh(now: try date(year: 2027, month: 1, day: 1), calendar: utc)
        #expect(months.selected == BudgetPeriod(year: 2027, month: 1))
        #expect(months.isCurrent)
    }

    @Test func browsingHistorySurvivesRolloverAndShortcutUsesTheNewMonth() throws {
        var months = BudgetMonthSelection(now: try date(month: 8), calendar: utc)
        months.showPrevious()

        months.refresh(now: try date(month: 9), calendar: utc)
        #expect(months.selected == BudgetPeriod(year: 2026, month: 7))
        #expect(months.current == BudgetPeriod(year: 2026, month: 9))

        months.showCurrent()
        #expect(months.selected == BudgetPeriod(year: 2026, month: 9))
    }

    @Test func clockCorrectionDoesNotLeaveASelectedMonthInTheFuture() throws {
        var months = BudgetMonthSelection(now: try date(month: 10), calendar: utc)
        months.showPrevious()

        months.refresh(now: try date(month: 8), calendar: utc)
        #expect(months.selected == BudgetPeriod(year: 2026, month: 8))
        #expect(months.isCurrent)
        #expect(!months.canMoveForward)
    }
}
