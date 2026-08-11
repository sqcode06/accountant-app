import SwiftUI
import AccountantCore

/// Tap an account, see what happened in it.
///
/// This is the screen the app was missing. Tapping an account previously opened a
/// rename dialog, so the most natural gesture in a finance app led nowhere, while
/// `ledger.statement(for:)` sat written and tested with no caller.
struct AccountDetailView: View {
    @EnvironmentObject private var appState: AppState

    let accountID: AccountID

    @State private var isPresentingEditor = false

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                ContentUnavailableView(
                    "Account unavailable",
                    systemImage: "questionmark.folder",
                    description: Text("This account is no longer in the ledger.")
                )
            }
        }
        // No explicit background: `.insetGrouped` already paints Theme.canvas,
        // and layering another one behind it just fights the list.
        .navigationTitle(account?.name ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let account {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPresentingEditor = true
                        } label: {
                            Label("Edit account", systemImage: "pencil")
                        }

                        if isReconcilable {
                            NavigationLink {
                                AccountReconcileView(accountID: accountID)
                                    .environmentObject(appState)
                            } label: {
                                Label("Reconcile", systemImage: "checkmark.circle")
                            }
                        }

                        Divider()

                        if account.status == .active {
                            Button(role: .destructive) {
                                Task { await appState.archiveAccount(id: accountID) }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        } else {
                            Button {
                                Task { await appState.restoreAccount(id: accountID) }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            if let account {
                AccountEditorView(mode: .edit(account))
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Content

    /// A `List` rather than a `ScrollView` specifically so rows get swipe actions —
    /// clearing an entry should be a flick, not a trip into a detail screen.
    private func content(_ snapshot: AccountDetailSnapshot) -> some View {
        List {
            Section {
                BalanceHeader(snapshot: snapshot)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if snapshot.entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "tray",
                        description: Text("Transactions involving this account will appear here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(snapshot.entries) { entry in
                        EntryRow(entry: entry)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Task {
                                        await appState.setCleared(
                                            !entry.isCleared,
                                            forAccount: accountID,
                                            in: entry.id
                                        )
                                    }
                                } label: {
                                    Label(
                                        entry.isCleared ? "Mark pending" : "Mark cleared",
                                        systemImage: entry.isCleared ? "arrow.uturn.backward" : "checkmark"
                                    )
                                }
                                .tint(entry.isCleared ? Theme.pending : Theme.cleared)
                            }
                    }
                } header: {
                    HStack {
                        Text("Activity")

                        Spacer()

                        if snapshot.pendingCount > 0 {
                            Text("\(snapshot.pendingCount) pending")
                                .foregroundStyle(Theme.pending)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Derived

    private var account: Account? {
        appState.ledger.accounts[accountID]
    }

    private var snapshot: AccountDetailSnapshot? {
        guard let account else { return nil }

        return AccountDetailSnapshot.make(
            from: appState.ledger,
            account: account,
            currency: appState.currency(for: account)
        )
    }

    /// Only balance-bearing accounts have statements to reconcile against.
    private var isReconcilable: Bool {
        guard let account else { return false }
        return account.status == .active && (account.kind == .asset || account.kind == .liability)
    }
}

// MARK: - Header

private struct BalanceHeader: View {
    let snapshot: AccountDetailSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            HStack {
                Text(snapshot.account.kind.displayName)
                    .fieldLabel()

                Spacer()

                Text(snapshot.currency.code)
                    .fieldLabel(Theme.accent)
            }

            MoneyText(money: snapshot.balance, role: .balance, font: .figureHero)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            // Only worth splitting out when the two figures actually differ.
            if snapshot.hasPending {
                VStack(spacing: Metrics.Space.s) {
                    Hairline()

                    HStack(alignment: .top) {
                        splitColumn(
                            label: "Cleared",
                            money: snapshot.clearedBalance,
                            tint: Theme.cleared
                        )

                        Spacer()

                        splitColumn(
                            label: "Pending",
                            money: snapshot.pendingBalance,
                            tint: Theme.pending,
                            alignment: .trailing
                        )
                    }
                }
            }
        }
        .card(padding: Metrics.Space.xl)
    }

    private func splitColumn(
        label: String,
        money: Money,
        tint: Color,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: Metrics.Space.xs) {
            Text(label)
                .fieldLabel(tint)

            MoneyText(money: money, font: .figureTrailing)
        }
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry: AccountDetailSnapshot.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.m) {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                Text(entry.title)
                    .font(.uiBody)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                HStack(spacing: Metrics.Space.xs) {
                    Text(DateDisplay.transactionDate(entry.date))

                    if !entry.counterparties.isEmpty {
                        Text("·")
                        Text(entry.counterparties.joined(separator: ", "))
                            .lineLimit(1)
                    }

                    if entry.isDraft {
                        Text("·")
                        Text("Draft")
                    }
                }
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: Metrics.Space.s)

            VStack(alignment: .trailing, spacing: Metrics.Space.xs) {
                MoneyText(
                    money: entry.delta,
                    role: entry.isInflow ? .inflow : .outflow,
                    showsPositiveSign: true
                )

                // Running balance in the trailing column, with a pending marker.
                // Uncleared entries are the ones that need attention, so only they
                // carry a mark — a checkmark on every settled row is just clutter.
                HStack(spacing: Metrics.Space.xs) {
                    if !entry.isCleared {
                        Circle()
                            .fill(Theme.pending)
                            .frame(width: 5, height: 5)
                    }

                    MoneyText(money: entry.runningBalance, font: .figureTrailing)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .padding(.vertical, Metrics.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.isCleared ? "Cleared" : "Pending")
    }
}

// MARK: - Kind bridging

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountDetailView(accountID: AccountDetailPreviewData.bankID)
            .environmentObject(
                AppState(repository: AccountDetailPreviewRepository())
            )
    }
}

private enum AccountDetailPreviewData {
    static let bankID = AccountID()
    static let groceriesID = AccountID()

    /// A bank account with one cleared and one pending expense, so the header's
    /// cleared/pending split and both row states are visible in the canvas.
    ///
    /// An empty ledger on failure is fine here — the preview then renders the
    /// empty state, which is also worth looking at.
    static func makeLedger() -> Ledger {
        (try? buildLedger()) ?? Ledger()
    }

    private static func buildLedger() throws -> Ledger {
        var ledger = Ledger()
        let eur = Currency("EUR")

        ledger.addAccount(
            Account(id: bankID, name: "Swedbank", kind: .asset, currency: eur)
        )
        ledger.addAccount(
            Account(id: groceriesID, name: "Groceries", kind: .expense)
        )

        let cleared = try Transaction.draftExpense(
            paidFrom: bankID,
            category: groceriesID,
            amount: Money(Decimal(24.90), currency: eur),
            date: Date(timeIntervalSince1970: 1_760_000_000),
            memo: "Rimi"
        )

        let pending = try Transaction.draftExpense(
            paidFrom: bankID,
            category: groceriesID,
            amount: Money(Decimal(8.40), currency: eur),
            date: Date(timeIntervalSince1970: 1_760_200_000),
            memo: "Bolt Food"
        )

        try ledger.addTransaction(cleared)
        try ledger.addTransaction(pending)
        try ledger.finalizeTransaction(id: cleared.id)
        try ledger.setCleared(true, forAccount: bankID, in: cleared.id)

        return ledger
    }
}

private struct AccountDetailPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        AccountDetailPreviewData.makeLedger()
    }

    func save(_ ledger: Ledger) async throws {}
}
