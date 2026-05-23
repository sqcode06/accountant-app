import Foundation
import AccountantCore

struct DashboardSnapshot {
    let currency: Currency
    let accountSummaries: [AccountBalanceSummary]
    let kindSummaries: [AccountKindBalanceSummary]
    let archivedAccountCount: Int

    static func make(
        from ledger: Ledger,
        currency: Currency,
        asOf date: Date
    ) -> DashboardSnapshot {
        let accountSummaries = ledger.accountBalanceSummaries(
            currency: currency,
            asOf: date,
            includeDrafts: false,
            includeArchived: false
        )

        return DashboardSnapshot(
            currency: currency,
            accountSummaries: accountSummaries,
            kindSummaries: makeKindSummaries(from: accountSummaries, currency: currency),
            archivedAccountCount: ledger.accounts.values.filter { $0.status == .archived }.count
        )
    }

    var activeAccountCount: Int {
        accountSummaries.count
    }

    var assetLiabilityAmount: Decimal {
        kindAmount(.asset) + kindAmount(.liability)
    }

    var heroSubtitle: String {
        let activeText = "\(activeAccountCount) active account\(activeAccountCount == 1 ? "" : "s")"

        if archivedAccountCount == 0 {
            return activeText
        }

        return "\(activeText) · \(archivedAccountCount) archived"
    }

    func kindAmount(_ kind: AccountKind) -> Decimal {
        kindSummaries.first { $0.kind == kind }?.balance.amount ?? .zero
    }

    func userFacingAmount(for kind: AccountKind) -> Decimal {
        let rawAmount = kindAmount(kind)

        switch kind {
        case .income:
            return -rawAmount
        default:
            return rawAmount
        }
    }

    func accountCountCaption(for kind: AccountKind) -> String {
        let count = kindSummaries.first { $0.kind == kind }?.accountCount ?? 0
        return "\(count) account\(count == 1 ? "" : "s")"
    }

    private static func makeKindSummaries(
        from accountSummaries: [AccountBalanceSummary],
        currency: Currency
    ) -> [AccountKindBalanceSummary] {
        var grouped: [AccountKind: (amount: Decimal, count: Int)] = [:]

        for summary in accountSummaries {
            let current = grouped[summary.account.kind] ?? (amount: .zero, count: 0)
            grouped[summary.account.kind] = (
                amount: current.amount + summary.balance.amount,
                count: current.count + 1
            )
        }

        return grouped.keys
            .sorted {
                AccountKindCatalog.sortIndex(for: $0) < AccountKindCatalog.sortIndex(for: $1)
            }
            .map { kind in
                let value = grouped[kind] ?? (amount: .zero, count: 0)

                return AccountKindBalanceSummary(
                    kind: kind,
                    currency: currency,
                    balance: Money(value.amount, currency: currency),
                    accountCount: value.count
                )
            }
    }
}
