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

        let kindSummaries = ledger.accountKindBalanceSummaries(
            currency: currency,
            asOf: date,
            includeDrafts: false,
            includeArchived: false
        )
        .sorted {
            AccountKindCatalog.sortIndex(for: $0.kind) < AccountKindCatalog.sortIndex(for: $1.kind)
        }

        return DashboardSnapshot(
            currency: currency,
            accountSummaries: accountSummaries,
            kindSummaries: kindSummaries,
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
}
