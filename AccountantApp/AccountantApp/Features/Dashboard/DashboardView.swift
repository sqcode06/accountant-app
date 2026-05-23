import SwiftUI
import AccountantCore

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    // Temporary until app settings / preferred display currency exist.
    private let displayCurrency = Currency("EUR")

    var body: some View {
        let snapshot = dashboardSnapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DashboardHeroCard(
                    title: "Net position",
                    amount: Money(snapshot.assetLiabilityAmount, currency: snapshot.currency),
                    subtitle: snapshot.heroSubtitle
                )

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    DashboardMetricCard(
                        title: "Assets",
                        amount: Money(snapshot.kindAmount(.asset), currency: snapshot.currency),
                        systemImage: AccountKind.asset.systemImageName,
                        caption: snapshot.accountCountCaption(for: .asset)
                    )

                    DashboardMetricCard(
                        title: "Liabilities",
                        amount: Money(snapshot.kindAmount(.liability), currency: snapshot.currency),
                        systemImage: AccountKind.liability.systemImageName,
                        caption: snapshot.accountCountCaption(for: .liability)
                    )

                    DashboardMetricCard(
                        title: "Income",
                        amount: Money(snapshot.userFacingAmount(for: .income), currency: snapshot.currency),
                        systemImage: AccountKind.income.systemImageName,
                        caption: snapshot.accountCountCaption(for: .income)
                    )

                    DashboardMetricCard(
                        title: "Expenses",
                        amount: Money(snapshot.kindAmount(.expense), currency: snapshot.currency),
                        systemImage: AccountKind.expense.systemImageName,
                        caption: snapshot.accountCountCaption(for: .expense)
                    )
                }

                DashboardSectionHeader(
                    title: "Accounts",
                    subtitle: "Active balances in \(snapshot.currency.code)"
                )

                if snapshot.accountSummaries.isEmpty {
                    DashboardEmptyCard(
                        title: "No active accounts yet",
                        message: "Create accounts from the Accounts tab and they will appear here."
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(snapshot.accountSummaries, id: \.account.id) { summary in
                            DashboardAccountRow(summary: summary)
                        }
                    }
                }

                DashboardSectionHeader(
                    title: "By kind",
                    subtitle: "Raw ledger groups, with income shown as positive for readability"
                )

                if snapshot.kindSummaries.isEmpty {
                    DashboardEmptyCard(
                        title: "No kind totals yet",
                        message: "Totals will appear once accounts exist."
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(snapshot.kindSummaries, id: \.kind) { summary in
                            DashboardKindRow(
                                summary: summary,
                                amount: Money(
                                    snapshot.userFacingAmount(for: summary.kind),
                                    currency: snapshot.currency
                                )
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.purple.opacity(0.08),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var dashboardSnapshot: DashboardSnapshot {
        let asOf = Date()

        let accountSummaries = appState.ledger.accountBalanceSummaries(
            currency: displayCurrency,
            asOf: asOf,
            includeDrafts: false,
            includeArchived: false
        )

        return DashboardSnapshot(
            currency: displayCurrency,
            accountSummaries: accountSummaries,
            kindSummaries: makeKindSummaries(from: accountSummaries),
            archivedAccountCount: appState.ledger.accounts.values.filter { $0.status == .archived }.count
        )
    }

    private func makeKindSummaries(
        from accountSummaries: [AccountBalanceSummary]
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
                    currency: displayCurrency,
                    balance: Money(value.amount, currency: displayCurrency),
                    accountCount: value.count
                )
            }
    }
}

private struct DashboardSnapshot {
    let currency: Currency
    let accountSummaries: [AccountBalanceSummary]
    let kindSummaries: [AccountKindBalanceSummary]
    let archivedAccountCount: Int

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

private struct DashboardHeroCard: View {
    let title: String
    let amount: Money
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(amount.currency.code)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Text(MoneyDisplay.string(amount))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let amount: Money
    let systemImage: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(MoneyDisplay.string(amount))
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.7)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DashboardSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private struct DashboardAccountRow: View {
    let summary: AccountBalanceSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.account.kind.systemImageName)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.account.name)
                    .font(.headline)

                Text(summary.account.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(MoneyDisplay.string(summary.balance))
                .font(.headline.monospacedDigit())
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DashboardKindRow: View {
    let summary: AccountKindBalanceSummary
    let amount: Money

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.kind.systemImageName)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.kind.displayName)
                    .font(.headline)

                Text("\(summary.accountCount) account\(summary.accountCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(MoneyDisplay.string(amount))
                .font(.headline.monospacedDigit())
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DashboardEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "chart.pie",
            description: Text(message)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        DashboardView()
            .environmentObject(AppState(repository: DashboardPreviewRepository()))
    }
}

private struct DashboardPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}
