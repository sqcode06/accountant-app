import SwiftUI
import AccountantCore

/// Spending against monthly limits.
///
/// Written to be encouraging rather than punitive. It leads with what is *left*
/// rather than what is gone, because "€182 left" invites a decision and "€118
/// spent" only invites guilt — and an app that makes you feel bad is an app you
/// stop opening, which is the only real failure mode for a budget.
struct BudgetView: View {
    @EnvironmentObject private var appState: AppState

    @State private var period = BudgetPeriod.containing(Date())
    @State private var editingCategory: EditableCategory?
    @State private var isPresentingCategoryPicker = false

    /// The report and the category list are built once here and passed down.
    ///
    /// They used to be computed properties read straight from `body`, which meant
    /// SwiftUI re-evaluated them on every reference: sixteen full `BudgetReport`
    /// builds per render, each one walking every transaction and every posting in
    /// the ledger, plus three sorts of the account list. On a ledger with any real
    /// history that is the difference between a screen that scrolls and one that
    /// stutters.
    var body: some View {
        let report = appState.budgetReport(for: period)
        let categories = budgetableCategories

        return Group {
            if report.lines.isEmpty && report.unbudgeted.isEmpty {
                emptyState(hasCategories: !categories.isEmpty)
            } else {
                content(report)
            }
        }
        .navigationTitle("Budget")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingCategoryPicker = true
                } label: {
                    Label("Set a limit", systemImage: "plus")
                }
                .disabled(categories.isEmpty)
            }
        }
        .sheet(isPresented: $isPresentingCategoryPicker) {
            BudgetCategoryPicker(categories: categories) { category in
                isPresentingCategoryPicker = false
                editingCategory = EditableCategory(account: category)
            }
        }
        .sheet(item: $editingCategory) { editable in
            BudgetTargetEditor(
                category: editable.account,
                period: period,
                currentAmount: appState.budget.target(for: editable.id, in: period)?.amount
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Content

    private func content(_ report: BudgetReport) -> some View {
        List {
            Section {
                monthHeader(report)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !report.lines.isEmpty {
                Section("Categories") {
                    ForEach(report.lines, id: \.account.id) { line in
                        BudgetLineRow(line: line)
                            .contentShape(Rectangle())
                            .onTapGesture { editingCategory = EditableCategory(account: line.account) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await appState.removeBudgetTarget(
                                            for: line.account.id,
                                            from: period
                                        )
                                    }
                                } label: {
                                    Label("Stop", systemImage: "xmark")
                                }
                            }
                    }
                }
            }

            if !report.unbudgeted.isEmpty {
                Section {
                    ForEach(report.unbudgeted, id: \.account.id) { line in
                        Button {
                            editingCategory = EditableCategory(account: line.account)
                        } label: {
                            HStack {
                                Text(line.account.name)
                                    .font(.uiRowTitle)
                                    .foregroundStyle(Theme.ink)

                                Spacer()

                                MoneyText(money: line.spent, role: .outflow)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Not budgeted")
                } footer: {
                    Text("Spending here counts against nothing. Set a limit to bring it into the plan.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Header

    private func monthHeader(_ report: BudgetReport) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            HStack {
                Button {
                    period = period.previous
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(monthTitle)
                    .font(.uiTitle)
                    .foregroundStyle(Theme.ink)

                Spacer()

                Button {
                    period = period.next
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(period >= BudgetPeriod.containing(Date()))
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.accent)

            if report.lines.isEmpty {
                Text("No limits set for this month.")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                FigureBlock(
                    label: headlineLabel(report),
                    money: headlineMoney(report),
                    role: report.totalRemaining.amount < .zero ? .balance : .plain,
                    font: .figureHero
                )

                BudgetBar(
                    progress: overallProgress(report),
                    isOverspent: report.totalRemaining.amount < .zero
                )

                HStack {
                    Text("\(MoneyDisplay.string(report.totalSpent)) spent")
                    Spacer()
                    Text("of \(MoneyDisplay.string(report.totalTarget))")
                }
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
            }
        }
        .heroCard()
        .padding(.vertical, Metrics.Space.s)
    }

    private func emptyState(hasCategories: Bool) -> some View {
        ContentUnavailableView {
            Label("No budget yet", systemImage: "chart.bar")
        } description: {
            Text("Set a monthly limit on the categories you want to keep an eye on. You do not need to budget everything — start with the two or three that get away from you.")
        } actions: {
            Button {
                isPresentingCategoryPicker = true
            } label: {
                Label("Set a limit", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasCategories)
        }
    }

    // MARK: - Derived

    /// Leads with what remains. Flips to the overspend only once there is one,
    /// where the honest number is the one worth showing.
    private func headlineLabel(_ report: BudgetReport) -> String {
        report.totalRemaining.amount < .zero ? "Over budget" : "Left this month"
    }

    private func headlineMoney(_ report: BudgetReport) -> Money {
        let remaining = report.totalRemaining

        guard remaining.amount < .zero else { return remaining }
        return Money(-remaining.amount, currency: remaining.currency)
    }

    private func overallProgress(_ report: BudgetReport) -> Double {
        guard report.totalTarget.amount > .zero else { return 0 }

        return max(
            0,
            (report.totalSpent.amount as NSDecimalNumber).doubleValue
                / (report.totalTarget.amount as NSDecimalNumber).doubleValue
        )
    }

    private var monthTitle: String {
        guard let date = period.dateInterval()?.start else { return "" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private var budgetableCategories: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && $0.kind.isBudgetable }
            .sortedForDisplay()
    }
}

// MARK: - Row

private struct BudgetLineRow: View {
    let line: BudgetLine

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.s) {
            HStack {
                Text(line.account.name)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)

                Spacer()

                Text(statusText)
                    .font(.uiLabel)
                    .foregroundStyle(statusColor)
            }

            BudgetBar(progress: line.progress, isOverspent: line.isOverspent)

            HStack {
                Text(MoneyDisplay.string(line.spent))
                Spacer()
                Text("of \(MoneyDisplay.string(line.target))")
            }
            .font(.uiCaption)
            .foregroundStyle(Theme.inkMuted)
        }
        .padding(.vertical, Metrics.Space.s)
    }

    private var statusText: String {
        if let overspend = line.overspend {
            return "\(MoneyDisplay.string(overspend)) over"
        }

        return "\(MoneyDisplay.string(line.remaining)) left"
    }

    private var statusColor: Color {
        if line.isOverspent { return Theme.deficit }
        if line.progress >= 0.8 { return Theme.pending }
        return Theme.inkMuted
    }
}

// MARK: - Category picker

private struct BudgetCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Account]
    let onSelect: (Account) -> Void

    var body: some View {
        NavigationStack {
            List(categories, id: \.id) { category in
                Button {
                    onSelect(category)
                } label: {
                    Text(category.name)
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.ink)
                }
            }
            .navigationTitle("Which category?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Wrapper so `.sheet(item:)` can carry an account.
///
/// `Account` is not `Identifiable` and adding a retroactive conformance here would
/// be both wrong — it already has a stored `id`, so a computed one is a
/// redeclaration — and rude, since it would collide the day the core adds its own.
struct EditableCategory: Identifiable {
    let account: Account
    var id: AccountID { account.id }
}
