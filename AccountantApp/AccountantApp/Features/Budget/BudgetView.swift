import SwiftUI
import UIKit
import AccountantCore

/// Spending against monthly limits.
///
/// Written to be encouraging rather than punitive. It leads with what is *left*
/// rather than what is gone, because "€182 left" invites a decision and "€118
/// spent" only invites guilt — and an app that makes you feel bad is an app you
/// stop opening, which is the only real failure mode for a budget.
struct BudgetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appClock) private var clock

    @State private var months = BudgetMonthSelection()
    @State private var presentedSheet: BudgetSheet?

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

        return content(report, hasCategories: !categories.isEmpty)
        .navigationTitle("Budget")
        .onAppear { months.refresh(now: clock.now()) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { months.refresh(now: clock.now()) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            months.refresh(now: clock.now())
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedSheet = .categoryPicker
                } label: {
                    Label("Set a limit", systemImage: "plus")
                }
                .disabled(categories.isEmpty)
                .accessibilityIdentifier("budget.setLimit.toolbar")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .categoryPicker:
                BudgetCategoryPicker(categories: categories) { category in
                    presentedSheet = .editor(
                        EditableCategory(account: category, period: period)
                    )
                }
            case let .editor(editable):
                BudgetTargetEditor(
                    category: editable.account,
                    period: editable.period,
                    currentAmount: appState.budget.target(
                        for: editable.id,
                        in: editable.period
                    )?.amount
                )
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Content

    private func content(_ report: BudgetReport, hasCategories: Bool) -> some View {
        List {
            // Keep navigation visible even when the selected month has no data.
            // Otherwise browsing before the first limit strands the user there.
            Section {
                monthHeader(report)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if report.lines.isEmpty && report.unbudgeted.isEmpty {
                Section {
                    emptyState(hasCategories: hasCategories)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !report.lines.isEmpty {
                Section("Categories") {
                    ForEach(report.lines, id: \.account.id) { line in
                        BudgetLineRow(line: line)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                presentedSheet = .editor(
                                    EditableCategory(account: line.account, period: period)
                                )
                            }
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
                            presentedSheet = .editor(
                                EditableCategory(account: line.account, period: period)
                            )
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
                    months.showPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Text(monthTitle)
                    .font(.uiTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("budget.month.title")

                Spacer()

                Button {
                    months.showNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next month")
                .disabled(!months.canMoveForward)
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.accent)

            if !months.isCurrent {
                HStack {
                    Text("Viewing a past month")
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Button("Back to this month") { months.showCurrent() }
                        .foregroundStyle(Theme.accent)
                }
                .font(.uiCaption)
            }

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
                .accessibilityIdentifier("budget.total.remaining")

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

                Text("Includes draft and confirmed spending.")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        // Automatic List buttons can make the whole row activate its buttons.
        // Each month control must respond only to a tap on that control.
        .buttonStyle(.borderless)
        .heroCard()
        .padding(.vertical, Metrics.Space.s)
    }

    private func emptyState(hasCategories: Bool) -> some View {
        ContentUnavailableView {
            Label("No budget for this month", systemImage: "chart.bar")
        } description: {
            Text("Set a limit on the categories you want to keep an eye on. Limits repeat every month from their start month until you change or stop them.")
        } actions: {
            Button {
                presentedSheet = .categoryPicker
            } label: {
                Label("Set a limit", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasCategories)
            .accessibilityIdentifier("budget.setLimit.empty")
        }
    }

    // MARK: - Derived

    private var period: BudgetPeriod { months.selected }

    /// Leads with what remains. Flips to the overspend only once there is one,
    /// where the honest number is the one worth showing.
    private func headlineLabel(_ report: BudgetReport) -> String {
        if report.totalRemaining.amount < .zero { return "Over budget" }
        return months.isCurrent ? "Left this month" : "Left in \(monthTitle)"
    }

    private func headlineMoney(_ report: BudgetReport) -> Money {
        let remaining = report.totalRemaining

        guard remaining.amount < .zero else { return remaining }
        return Money(-remaining.amount, currency: remaining.currency)
    }

    private func overallProgress(_ report: BudgetReport) -> Double {
        guard report.totalTarget.amount > .zero else { return 0 }

        let progress = (report.totalSpent.amount as NSDecimalNumber).doubleValue
            / (report.totalTarget.amount as NSDecimalNumber).doubleValue

        guard progress.isFinite else { return progress > 0 ? 1 : 0 }
        return max(0, progress)
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

private enum BudgetSheet: Identifiable {
    case categoryPicker
    case editor(EditableCategory)

    var id: String {
        switch self {
        case .categoryPicker:
            return "category-picker"
        case let .editor(editable):
            return "editor-\(editable.id.rawValue.uuidString)-\(editable.period.year)-\(editable.period.month)"
        }
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
                    .accessibilityIdentifier("budget.line.remaining")
            }

            BudgetBar(progress: line.progress, isOverspent: line.isOverspent)
                .accessibilityIdentifier("budget.line.progress")

            HStack {
                Text(MoneyDisplay.string(line.spent))
                    .accessibilityIdentifier("budget.line.spent")
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
                .accessibilityIdentifier("budget.category.\(category.id.rawValue.uuidString)")
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
    /// Keep an open editor on the month it was opened for across date changes.
    let period: BudgetPeriod
    var id: AccountID { account.id }
}
