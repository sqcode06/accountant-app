import SwiftUI
import AccountantCore

/// Record a purchase in two gestures: type the amount, tap the category.
///
/// Deliberately expense-only. Spending is almost everything a person records
/// during a day, and adding income and transfers here would mean a type switcher
/// on screen that 95% of captures skip past. Those live in the full editor.
///
/// Everything captured here is a **draft**. That is the point: it costs nothing to
/// be slightly wrong at the till, because the evening review is where entries get
/// checked and confirmed. The account and category are best guesses that are
/// trivial to fix later, so nothing here blocks on getting them right.
struct QuickEntryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var entry = AmountEntry()
    @State private var selectedAccountID: AccountID?
    @State private var isPresentingAllCategories = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amountDisplay

                Spacer(minLength: Metrics.Space.m)

                if categories.isEmpty {
                    missingCategories
                } else {
                    categoryStrip
                }

                AmountKeypad(entry: $entry)
                    .padding(.horizontal, Metrics.Space.l)
                    .padding(.bottom, Metrics.Space.l)
            }
            .background(Theme.canvas)
            .navigationTitle("Spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    accountPicker
                }
            }
            .appErrorAlert()
            .onAppear(perform: selectDefaultAccountIfNeeded)
            .sheet(isPresented: $isPresentingAllCategories) {
                CategoryPickerSheet(categories: categories) { category in
                    isPresentingAllCategories = false
                    capture(into: category)
                }
            }
        }
    }

    // MARK: - Amount

    private var amountDisplay: some View {
        VStack(spacing: Metrics.Space.xs) {
            MoneyText(
                money: entry.money(in: currency),
                role: entry.isEmpty ? .plain : .outflow,
                font: .figureHero
            )
            .opacity(entry.isEmpty ? 0.3 : 1)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.18), value: entry.minorUnits)

            Text(entry.isEmpty ? "Enter an amount" : "Tap a category to save")
                .fieldLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.Space.hero)
    }

    // MARK: - Account

    private var accountPicker: some View {
        Menu {
            Picker("Paid from", selection: $selectedAccountID) {
                ForEach(spendingAccounts, id: \.id) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
        } label: {
            HStack(spacing: Metrics.Space.xs) {
                Text(selectedAccount?.name ?? "Account")
                    .font(.uiLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.inkMuted)
        }
        .disabled(spendingAccounts.count <= 1)
    }

    // MARK: - Categories

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.Space.s) {
                ForEach(frequentCategories, id: \.id) { category in
                    CategoryChip(name: category.name, isEnabled: canSave) {
                        capture(into: category)
                    }
                }

                if categories.count > frequentCategories.count {
                    CategoryChip(name: "More", isEnabled: canSave, isSecondary: true) {
                        isPresentingAllCategories = true
                    }
                }
            }
            .padding(.horizontal, Metrics.Space.l)
        }
        .padding(.bottom, Metrics.Space.l)
    }

    private var missingCategories: some View {
        Text("Add an expense category before recording spending.")
            .font(.uiCaption)
            .foregroundStyle(Theme.inkMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Metrics.Space.xl)
            .padding(.bottom, Metrics.Space.l)
    }

    // MARK: - Saving

    private var canSave: Bool {
        !entry.isEmpty && selectedAccountID != nil && !isSaving
    }

    private func capture(into category: Account) {
        guard canSave, let selectedAccountID else { return }

        isSaving = true

        Task {
            let saved = await appState.createDraftExpense(
                paidFrom: selectedAccountID,
                category: category.id,
                amount: entry.money(in: currency),
                date: Date(),
                memo: nil
            )

            isSaving = false

            if saved {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dismiss()
            }
        }
    }

    // MARK: - Derived

    private var currency: Currency {
        guard let selectedAccount else { return appState.displayCurrency }
        return appState.currency(for: selectedAccount)
    }

    private var selectedAccount: Account? {
        selectedAccountID.flatMap { appState.ledger.accounts[$0] }
    }

    /// Accounts money can leave from.
    private var spendingAccounts: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && ($0.kind == .asset || $0.kind == .liability) }
            .sortedForDisplay()
    }

    private var categories: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && $0.kind == .expense }
            .sortedForDisplay()
    }

    /// Categories ordered by how often they are actually used, so the common ones
    /// sit under the thumb. Zero configuration — the ledger already knows.
    private var frequentCategories: [Account] {
        let usage = usageCounts

        return categories
            .sorted { lhs, rhs in
                let lhsCount = usage[lhs.id] ?? 0
                let rhsCount = usage[rhs.id] ?? 0

                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(6)
            .map { $0 }
    }

    private var usageCounts: [AccountID: Int] {
        var counts: [AccountID: Int] = [:]

        for transaction in appState.ledger.transactions {
            for posting in transaction.postings {
                counts[posting.accountID, default: 0] += 1
            }
        }

        return counts
    }

    private func selectDefaultAccountIfNeeded() {
        guard selectedAccountID == nil || appState.ledger.accounts[selectedAccountID!] == nil else {
            return
        }

        let usage = usageCounts

        selectedAccountID = spendingAccounts
            .max { (usage[$0.id] ?? 0) < (usage[$1.id] ?? 0) }?
            .id
    }
}

// MARK: - Chip

private struct CategoryChip: View {
    let name: String
    let isEnabled: Bool
    var isSecondary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(.subheadline, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isSecondary ? Theme.inkMuted : Theme.inkInverse)
                .padding(.horizontal, Metrics.Space.l)
                .padding(.vertical, Metrics.Space.m)
                .background(
                    isSecondary ? Theme.surfaceSunken : Theme.accent,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

// MARK: - Full picker

private struct CategoryPickerSheet: View {
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
            .navigationTitle("Category")
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
