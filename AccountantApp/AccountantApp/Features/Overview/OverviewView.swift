import SwiftUI
import AccountantCore

/// "How much money do I have."
///
/// Merges the old Summary and Accounts tabs. They were split because the core had
/// a Query module and an account model, not because anyone wants to see balances
/// and the accounts holding them in two different places.
struct OverviewView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingEntry = false
    @State private var isPresentingNewAccount = false
    @State private var isPresentingImport = false

    /// Built once per render and threaded down.
    ///
    /// `OverviewSnapshot.make` walks every transaction and every posting *twice per
    /// currency* — once as of now, once as of the start of the month. Reading it
    /// from a computed property meant paying that for each of the five references
    /// in this file. `AccountSummary` already fixed the same mistake one layer
    /// down; this is the layer above it.
    var body: some View {
        let snapshot = self.snapshot
        let draftCount = appState.draftCount

        return Group {
            if snapshot.isEmpty {
                emptyState
            } else {
                content(snapshot, draftCount: draftCount)
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isPresentingEntry = true
                    } label: {
                        Label("Income or transfer", systemImage: "arrow.left.arrow.right")
                    }

                    Button {
                        isPresentingNewAccount = true
                    } label: {
                        Label("New account", systemImage: "folder.badge.plus")
                    }

                    Divider()

                    Button {
                        isPresentingImport = true
                    } label: {
                        Label("Import statement", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingEntry) {
            TransactionEntryView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $isPresentingNewAccount) {
            AccountEditorView(mode: .create)
                .environmentObject(appState)
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportFlow()
                .environmentObject(appState)
        }
    }

    private func content(_ snapshot: OverviewSnapshot, draftCount: Int) -> some View {
        List {
            // A timely nudge costs nothing and needs no notification permission.
            if draftCount > 0 {
                Section {
                    NavigationLink {
                        ReviewView()
                            .environmentObject(appState)
                    } label: {
                        HStack(spacing: Metrics.Space.m) {
                            Image(systemName: "tray.full")
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(reviewPromptTitle(draftCount))
                                    .font(.uiRowTitle)
                                    .foregroundStyle(Theme.ink)

                                Text("Check what you captured, then confirm")
                                    .font(.uiCaption)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                        }
                        .padding(.vertical, Metrics.Space.xs)
                    }
                }
            }

            ForEach(snapshot.groups) { group in
                Section {
                    NetPositionRow(group: group)

                    if group.hasMonthActivity {
                        MonthActivityRow(group: group)
                    }
                } header: {
                    Text(headerTitle(for: group, in: snapshot))
                }

                if !group.accounts.isEmpty {
                    Section("Accounts") {
                        ForEach(group.accounts, id: \.account.id) { summary in
                            NavigationLink {
                                AccountDetailView(accountID: summary.account.id)
                                    .environmentObject(appState)
                            } label: {
                                AccountSummaryRow(summary: summary)
                            }
                        }
                    }
                }
            }

            if snapshot.archivedAccountCount > 0 {
                Section {
                    NavigationLink {
                        ArchivedAccountsView()
                            .environmentObject(appState)
                    } label: {
                        Label(
                            "\(snapshot.archivedAccountCount) archived",
                            systemImage: "archivebox"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: "wallet.bifold")
        } description: {
            Text("Add the accounts your money actually sits in — a bank account, a card, cash — and balances will show up here.")
        } actions: {
            Button {
                isPresentingNewAccount = true
            } label: {
                Label("Add account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Only names the currency when there is more than one, so the common
    /// single-currency case does not carry redundant chrome.
    private func headerTitle(
        for group: OverviewSnapshot.CurrencyGroup,
        in snapshot: OverviewSnapshot
    ) -> String {
        snapshot.groups.count > 1
            ? "Net position · \(group.currency.code)"
            : "Net position"
    }

    private func reviewPromptTitle(_ count: Int) -> String {
        count == 1 ? "1 entry to review" : "\(count) entries to review"
    }

    private var snapshot: OverviewSnapshot {
        OverviewSnapshot.make(
            from: appState.ledger,
            fallbackCurrency: appState.displayCurrency
        )
    }
}

// MARK: - Rows

private struct NetPositionRow: View {
    let group: OverviewSnapshot.CurrencyGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.s) {
            HStack {
                Text("Net position")
                    .fieldLabel()

                Spacer()

                Text(group.currency.code)
                    .fieldLabel(Theme.accent)
            }

            MoneyText(money: group.netPosition, role: .balance, font: .figureHero)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")")
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.vertical, Metrics.Space.m)
    }
}

private struct MonthActivityRow: View {
    let group: OverviewSnapshot.CurrencyGroup

    var body: some View {
        HStack {
            column(
                title: "In this month",
                money: group.incomeThisMonth,
                role: .inflow
            )

            Spacer()

            Divider().frame(height: 28)

            Spacer()

            column(
                title: "Out this month",
                money: group.spentThisMonth,
                role: .outflow
            )
        }
        .padding(.vertical, Metrics.Space.xs)
    }

    private func column(title: String, money: Money, role: MoneyText.Role) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            MoneyText(money: money, role: role, font: .figureRow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountSummaryRow: View {
    let summary: AccountBalanceSummary

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.account.name)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(summary.account.kind.displayName)
                    .fieldLabel(Theme.inkFaint)
            }

            Spacer(minLength: Metrics.Space.s)

            MoneyText(money: summary.balance, role: .balance)
        }
    }
}

// MARK: - Archived

private struct ArchivedAccountsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let archived = self.archived

        return List {
            ForEach(archived, id: \.id) { account in
                NavigationLink {
                    AccountDetailView(accountID: account.id)
                        .environmentObject(appState)
                } label: {
                    HStack {
                        Text(account.name)
                        Spacer()
                        Text(account.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        Task { await appState.restoreAccount(id: account.id) }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if archived.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived accounts keep their history and can be restored at any time.")
                )
            }
        }
    }

    private var archived: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .archived }
            .sortedForDisplay()
    }
}
