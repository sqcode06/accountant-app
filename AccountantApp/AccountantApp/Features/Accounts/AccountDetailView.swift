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

                        // Reconcile moves in here once ReconciliationView is
                        // refactored to take an account (Phase 2). Deliberately
                        // absent rather than present and inert.

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
}

// MARK: - Header

private struct BalanceHeader: View {
    let snapshot: AccountDetailSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(spacing: Metrics.Space.s) {
                Image(systemName: snapshot.account.symbolName ?? snapshot.account.kind.systemImageName)
                    .font(.footnote)
                    .foregroundStyle(Theme.tint(for: snapshot.account.kind.tintCase))
                    .frame(width: 26, height: 26)
                    .background(
                        Theme.tint(for: snapshot.account.kind.tintCase).opacity(0.14),
                        in: Circle()
                    )

                Text(snapshot.account.kind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(snapshot.currency.code)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            MoneyText(
                money: snapshot.balance,
                role: .balance,
                font: .amountHero
            )
            .minimumScaleFactor(0.6)
            .lineLimit(1)

            if snapshot.hasPending {
                // Only worth saying when the two numbers actually differ.
                HStack(spacing: Metrics.Space.xs) {
                    Text("Cleared")
                        .foregroundStyle(.secondary)

                    MoneyText(money: snapshot.clearedBalance, font: .amountSecondary)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text("Pending")
                        .foregroundStyle(Theme.pending)

                    MoneyText(money: snapshot.pendingBalance, font: .amountSecondary)
                }
                .font(.caption)
            }
        }
        .card()
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry: AccountDetailSnapshot.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.m) {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                Text(entry.title)
                    .font(.body)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: Metrics.Space.s)

            VStack(alignment: .trailing, spacing: Metrics.Space.xs) {
                MoneyText(
                    money: entry.delta,
                    role: entry.isInflow ? .inflow : .outflow,
                    showsPositiveSign: true
                )

                HStack(spacing: 3) {
                    if entry.isCleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.cleared)
                    } else {
                        Circle()
                            .fill(Theme.pending)
                            .frame(width: 5, height: 5)
                    }

                    MoneyText(money: entry.runningBalance, font: .amountSecondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Metrics.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.isCleared ? "Cleared" : "Pending")
    }
}

// MARK: - Kind bridging

private extension AccountKind {
    /// Maps the core enum onto the theme's tint cases without the theme importing core.
    var tintCase: AccountKindTint {
        switch self {
        case .asset: .asset
        case .liability: .liability
        case .income: .income
        case .expense: .expense
        case .equity: .equity
        case .clearing: .clearing
        }
    }
}

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
    static func makeLedger() -> Ledger {
        var ledger = Ledger()
        let eur = Currency("EUR")

        ledger.addAccount(
            Account(id: bankID, name: "Swedbank", kind: .asset, currency: eur)
        )
        ledger.addAccount(
            Account(id: groceriesID, name: "Groceries", kind: .expense)
        )

        guard
            let cleared = try? Transaction.draftExpense(
                paidFrom: bankID,
                category: groceriesID,
                amount: Money(Decimal(24.90), currency: eur),
                date: Date(timeIntervalSince1970: 1_760_000_000),
                memo: "Rimi"
            ),
            let pending = try? Transaction.draftExpense(
                paidFrom: bankID,
                category: groceriesID,
                amount: Money(Decimal(8.40), currency: eur),
                date: Date(timeIntervalSince1970: 1_760_200_000),
                memo: "Bolt Food"
            ),
            (try? ledger.addTransaction(cleared)) != nil,
            (try? ledger.addTransaction(pending)) != nil
        else {
            return ledger
        }

        try? ledger.finalizeTransaction(id: cleared.id)
        try? ledger.setCleared(true, forAccount: bankID, in: cleared.id)

        return ledger
    }
}

private struct AccountDetailPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        AccountDetailPreviewData.makeLedger()
    }

    func save(_ ledger: Ledger) async throws {}
}
