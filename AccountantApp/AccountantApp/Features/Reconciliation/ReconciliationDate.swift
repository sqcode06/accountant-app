import Foundation

enum ReconciliationDate {
    /// Returns the final instant in the calendar day containing `date`.
    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        // Ask for the day's actual boundary. Adding a day to its start is
        // incorrect when a daylight-saving transition skips midnight.
        guard let nextStart = calendar.dateInterval(of: .day, for: date)?.end else {
            return date
        }

        // Date is a fractional-second value. Using one whole second here would
        // discard valid transactions in the final fractional second of the day.
        return Date(timeIntervalSinceReferenceDate: nextStart.timeIntervalSinceReferenceDate.nextDown)
    }
}
