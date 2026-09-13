import Foundation
import AccountantCore

/// Follows the current month until the user deliberately browses history.
struct BudgetMonthSelection {
    private(set) var current: BudgetPeriod
    private(set) var selected: BudgetPeriod

    init(now: Date = Date(), calendar: Calendar = .current) {
        let period = BudgetPeriod.containing(now, calendar: calendar)
        current = period
        selected = period
    }

    var isCurrent: Bool { selected == current }
    var canMoveForward: Bool { selected < current }

    mutating func showPrevious() {
        selected = selected.previous
    }

    mutating func showNext() {
        guard canMoveForward else { return }
        selected = selected.next
    }

    mutating func showCurrent() {
        selected = current
    }

    /// Called on appearance, foregrounding, and system date changes. Keep a
    /// deliberately selected past month, but let the current month roll forward.
    mutating func refresh(now: Date = Date(), calendar: Calendar = .current) {
        let updated = BudgetPeriod.containing(now, calendar: calendar)
        if isCurrent || selected > updated {
            selected = updated
        }
        current = updated
    }
}
