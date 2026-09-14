import Foundation
import AccountantCore

/// What the Overview tab shows: how much money there is, grouped by currency.
///
/// Two deliberate departures from the old dashboard:
///
/// - **Grouped by currency, never summed across them.** There is no exchange rate
///   anywhere in this app, and inventing one to make a single headline number would
///   be a lie. Each currency gets its own net position.
/// - **No "by kind" section.** It exposed Equity and Clearing to someone trying to
///   see their money, under a subtitle written for a developer. Net position is
///   assets plus liabilities; categories belong to spending, not to "what do I have".
struct OverviewSnapshot {

    struct CurrencyGroup: Identifiable {
        let currency: Currency

        /// Assets plus liabilities. Liabilities carry negative balances under the
        /// double-entry convention, so this subtracts debt without special-casing.
        let netPosition: Money

        /// Balance-bearing accounts only, in the user's chosen order.
        let accounts: [AccountBalanceSummary]

        /// Month-to-date, shown as positive figures for readability.
        let incomeThisMonth: Money
        let spentThisMonth: Money

        var id: String { currency.code }

        var hasMonthActivity: Bool {
            incomeThisMonth.amount != .zero || spentThisMonth.amount != .zero
        }
    }

    let groups: [CurrencyGroup]
    let archivedAccountCount: Int

    var isEmpty: Bool { groups.allSatisfy(\.accounts.isEmpty) }

    static func make(
        from ledger: Ledger,
        fallbackCurrency: Currency,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OverviewSnapshot {
        let activeAccounts = ledger.accounts.values.filter { $0.status == .active }

        let balanceAccounts = activeAccounts.filter {
            $0.kind == .asset || $0.kind == .liability
        }

        // Currencies actually in use, plus the fallback so an empty ledger still
        // renders something coherent.
        var currencies = Set(balanceAccounts.compactMap(\.currency))
        if currencies.isEmpty {
            currencies.insert(fallbackCurrency)
        }

        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now

        let groups = currencies
            .sorted { $0.code < $1.code }
            .map { currency in
                makeGroup(
                    from: ledger,
                    currency: currency,
                    balanceAccounts: balanceAccounts,
                    now: now,
                    startOfMonth: startOfMonth
                )
            }

        return OverviewSnapshot(
            groups: groups,
            archivedAccountCount: activeAccounts.count < ledger.accounts.count
                ? ledger.accounts.values.filter { $0.status == .archived }.count
                : 0
        )
    }

    private static func makeGroup(
        from ledger: Ledger,
        currency: Currency,
        balanceAccounts: [Account],
        now: Date,
        startOfMonth: Date
    ) -> CurrencyGroup {
        let summaries = ledger.accountBalanceSummaries(
            currency: currency,
            asOf: now,
            includeDrafts: false,
            includeArchived: false
        )

        // An account belongs to this group when it declares this currency. Accounts
        // with no declared currency fall into the fallback group only.
        let accountIDs = Set(
            balanceAccounts
                .filter { ($0.currency ?? currency) == currency }
                .map(\.id)
        )

        let groupAccounts = summaries
            .filter { accountIDs.contains($0.account.id) }
            .sorted { lhs, rhs in
                if lhs.account.sortOrder != rhs.account.sortOrder {
                    return lhs.account.sortOrder < rhs.account.sortOrder
                }
                return lhs.account.name.localizedCaseInsensitiveCompare(rhs.account.name)
                    == .orderedAscending
            }

        let netPosition = groupAccounts.reduce(Decimal.zero) { $0 + $1.balance.amount }

        // Month-to-date is the cumulative balance now minus the balance at the start
        // of the month. Category balances are cumulative, so this is the delta.
        let openingSummaries = ledger.accountBalanceSummaries(
            currency: currency,
            asOf: startOfMonth,
            includeDrafts: false,
            includeArchived: false
        )

        let spent = total(of: .expense, in: summaries) - total(of: .expense, in: openingSummaries)

        // Income accounts hold negative balances under double-entry; flip for display.
        let earned = -(total(of: .income, in: summaries) - total(of: .income, in: openingSummaries))

        return CurrencyGroup(
            currency: currency,
            netPosition: Money(netPosition, currency: currency),
            accounts: groupAccounts,
            incomeThisMonth: Money(earned, currency: currency),
            spentThisMonth: Money(spent, currency: currency)
        )
    }

    private static func total(
        of kind: AccountKind,
        in summaries: [AccountBalanceSummary]
    ) -> Decimal {
        summaries
            .filter { $0.account.kind == kind }
            .reduce(Decimal.zero) { $0 + $1.balance.amount }
    }
}
