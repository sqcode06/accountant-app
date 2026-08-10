import Foundation

/// A calendar month, the unit budgets are set and judged in.
///
/// Stored as year and month rather than a `Date` on purpose. A `Date` pins an
/// instant, which drags timezone and DST into something that should be a plain
/// label: "August 2026" means the same thing regardless of where the phone is.
public struct BudgetPeriod: Hashable, Codable, Sendable, Comparable {
    public let year: Int

    /// 1...12.
    public let month: Int

    /// Normalises out-of-range months so arithmetic can be naive at call sites.
    public init(year: Int, month: Int) {
        let zeroBased = month - 1
        let yearOffset = Int(floor(Double(zeroBased) / 12.0))

        self.year = year + yearOffset
        self.month = zeroBased - (yearOffset * 12) + 1
    }

    public static func containing(_ date: Date, calendar: Calendar = .current) -> BudgetPeriod {
        let components = calendar.dateComponents([.year, .month], from: date)

        return BudgetPeriod(
            year: components.year ?? 1970,
            month: components.month ?? 1
        )
    }

    public var next: BudgetPeriod {
        BudgetPeriod(year: year, month: month + 1)
    }

    public var previous: BudgetPeriod {
        BudgetPeriod(year: year, month: month - 1)
    }

    /// Half-open range `[start, end)` covering this month.
    ///
    /// Half-open because a closed range would either include or exclude the final
    /// instant of the month depending on precision, and a purchase at 23:59:59.5 on
    /// the 31st belongs to this month either way.
    public func dateInterval(calendar: Calendar = .current) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: DateComponents(month: 1), to: start)
        else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let interval = dateInterval(calendar: calendar) else { return false }
        return date >= interval.start && date < interval.end
    }

    public static func < (lhs: BudgetPeriod, rhs: BudgetPeriod) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}
