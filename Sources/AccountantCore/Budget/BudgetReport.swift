import Foundation

/// One category's standing for a month.
public struct BudgetLine: Hashable, Sendable {
    public let account: Account
    public let target: Money
    public let spent: Money

    public init(account: Account, target: Money, spent: Money) {
        self.account = account
        self.target = target
        self.spent = spent
    }

    /// Target minus spent. Negative once the limit is passed.
    public var remaining: Money {
        Money(target.amount - spent.amount, currency: target.currency)
    }

    public var isOverspent: Bool {
        spent.amount > target.amount
    }

    /// Amount past the limit, or nil when still inside it.
    public var overspend: Money? {
        guard isOverspent else { return nil }
        return Money(spent.amount - target.amount, currency: target.currency)
    }

    /// Fraction of the target used, `0...` — can exceed 1 when overspent.
    ///
    /// Clamped at the bottom to 0 so a net refund does not render a negative bar.
    public var progress: Double {
        guard target.amount > .zero else { return 0 }

        let ratio = (spent.amount as NSDecimalNumber).doubleValue
            / (target.amount as NSDecimalNumber).doubleValue

        return max(0, ratio)
    }
}

/// Spending in a category with no target set.
///
/// Surfaced deliberately. Money leaking out through categories you never budgeted
/// is the most common reason a budget silently stops meaning anything.
public struct UnbudgetedLine: Hashable, Sendable {
    public let account: Account
    public let spent: Money

    public init(account: Account, spent: Money) {
        self.account = account
        self.spent = spent
    }
}

public struct BudgetReport: Hashable, Sendable {
    public let period: BudgetPeriod
    public let currency: Currency

    /// Budgeted categories, ordered by lowercased account name then stable ID.
    public let lines: [BudgetLine]

    /// Categories with spending but no target, same ordering.
    public let unbudgeted: [UnbudgetedLine]

    public let includesDrafts: Bool

    public init(
        period: BudgetPeriod,
        currency: Currency,
        lines: [BudgetLine],
        unbudgeted: [UnbudgetedLine],
        includesDrafts: Bool
    ) {
        self.period = period
        self.currency = currency
        self.lines = lines
        self.unbudgeted = unbudgeted
        self.includesDrafts = includesDrafts
    }

    public var totalTarget: Money {
        Money(lines.reduce(Decimal.zero) { $0 + $1.target.amount }, currency: currency)
    }

    /// Spending inside budgeted categories only.
    public var totalSpent: Money {
        Money(lines.reduce(Decimal.zero) { $0 + $1.spent.amount }, currency: currency)
    }

    public var totalRemaining: Money {
        Money(totalTarget.amount - totalSpent.amount, currency: currency)
    }

    public var unbudgetedSpent: Money {
        Money(unbudgeted.reduce(Decimal.zero) { $0 + $1.spent.amount }, currency: currency)
    }

    /// Everything spent this month across every category, budgeted or not.
    public var totalSpentIncludingUnbudgeted: Money {
        Money(totalSpent.amount + unbudgetedSpent.amount, currency: currency)
    }

    public var overspentLines: [BudgetLine] {
        lines.filter(\.isOverspent)
    }

    public var isWithinBudget: Bool {
        overspentLines.isEmpty
    }
}

public extension Ledger {
    /// Compares spending against targets for one month.
    ///
    /// Drafts count by default. An unfinalized purchase is still money that left,
    /// and a budget that ignores it flatters you — the opposite of useful. This is
    /// the reverse of the reconciliation default, which excludes drafts because it
    /// compares against a bank statement rather than against an intention.
    func budgetReport(
        budget: Budget,
        period: BudgetPeriod,
        currency: Currency,
        includeDrafts: Bool = true,
        calendar: Calendar = .current
    ) -> BudgetReport {
        guard let interval = period.dateInterval(calendar: calendar) else {
            return BudgetReport(
                period: period,
                currency: currency,
                lines: [],
                unbudgeted: [],
                includesDrafts: includeDrafts
            )
        }

        let spendByAccount = spend(
            in: interval,
            currency: currency,
            includeDrafts: includeDrafts
        )

        let activeTargets = budget.targets(in: period)
        let budgetedIDs = Set(activeTargets.map(\.accountID))

        let lines: [BudgetLine] = activeTargets
            .compactMap { target in
                guard let account = accounts[target.accountID] else { return nil }

                return BudgetLine(
                    account: account,
                    target: target.amount,
                    spent: Money(spendByAccount[target.accountID] ?? .zero, currency: currency)
                )
            }
            .sorted { categoryOrder($0.account, $1.account) }

        let unbudgeted: [UnbudgetedLine] = spendByAccount
            .compactMap { accountID, amount in
                guard
                    !budgetedIDs.contains(accountID),
                    amount != .zero,
                    let account = accounts[accountID],
                    account.kind.isBudgetable
                else {
                    return nil
                }

                return UnbudgetedLine(
                    account: account,
                    spent: Money(amount, currency: currency)
                )
            }
            .sorted { categoryOrder($0.account, $1.account) }

        return BudgetReport(
            period: period,
            currency: currency,
            lines: lines,
            unbudgeted: unbudgeted,
            includesDrafts: includeDrafts
        )
    }

    /// Totals postings per account within a half-open date interval, in one pass.
    private func spend(
        in interval: DateInterval,
        currency: Currency,
        includeDrafts: Bool
    ) -> [AccountID: Decimal] {
        var totals: [AccountID: Decimal] = [:]

        for tx in transactions {
            guard includeDrafts || tx.state == .finalized else { continue }
            guard tx.date >= interval.start, tx.date < interval.end else { continue }

            for posting in tx.postings where posting.money.currency == currency {
                guard accounts[posting.accountID]?.kind.isBudgetable == true else { continue }
                totals[posting.accountID, default: .zero] += posting.money.amount
            }
        }

        return totals
    }
}

/// Matches the deterministic ordering used by account summaries.
private func categoryOrder(_ lhs: Account, _ rhs: Account) -> Bool {
    let leftName = lhs.name.lowercased()
    let rightName = rhs.name.lowercased()

    if leftName != rightName { return leftName < rightName }

    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
}
