import SwiftUI
import AccountantCore

struct AccountListView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isShowingArchived = false
    @State private var isPresentingNewAccount = false
    @State private var accountToEdit: EditableAccount?

    var body: some View {
        Group {
            if visibleAccounts.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
            } else {
                List {
                    Section {
                        ForEach(visibleAccounts, id: \.id) { account in
                            AccountRowView(account: account)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    accountToEdit = EditableAccount(account: account)
                                }
                                .swipeActions(edge: .trailing) {
                                    if account.status == .active {
                                        Button(role: .destructive) {
                                            Task {
                                                await appState.archiveAccount(id: account.id)
                                            }
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                    } else {
                                        Button {
                                            Task {
                                                await appState.restoreAccount(id: account.id)
                                            }
                                        } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    } header: {
                        Text(isShowingArchived ? "All Accounts" : "Active Accounts")
                    } footer: {
                        if !isShowingArchived && archivedCount > 0 {
                            Text("\(archivedCount) archived account\(archivedCount == 1 ? "" : "s") hidden.")
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if archivedCount > 0 {
                    Button {
                        isShowingArchived.toggle()
                    } label: {
                        Label(
                            isShowingArchived ? "Hide Archived" : "Show Archived",
                            systemImage: isShowingArchived ? "archivebox.fill" : "archivebox"
                        )
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNewAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewAccount) {
            AccountEditorView(mode: .create)
                .environmentObject(appState)
        }
        .sheet(item: $accountToEdit) { editableAccount in
            AccountEditorView(mode: .edit(editableAccount.account))
                .environmentObject(appState)
        }
    }

    private var visibleAccounts: [Account] {
        sortedAccounts.filter { account in
            isShowingArchived || account.status == .active
        }
    }

    private var sortedAccounts: [Account] {
        appState.ledger.accounts.values.sortedForDisplay()
    }

    private var archivedCount: Int {
        appState.ledger.accounts.values.filter { $0.status == .archived }.count
    }

    private var emptyTitle: String {
        isShowingArchived ? "No accounts" : "No active accounts"
    }

    private var emptySystemImage: String {
        isShowingArchived ? "tray" : "tray.circle"
    }

    private var emptyDescription: String {
        if isShowingArchived {
            "Create your first account to start shaping the ledger."
        } else if archivedCount > 0 {
            "All accounts are archived. Show archived accounts to restore one."
        } else {
            "Create bank, cash, income, expense, or savings buckets."
        }
    }
}

private struct AccountRowView: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.kind.systemImageName)
                .frame(width: 28)
                .foregroundStyle(account.status == .active ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)

                Text(account.kind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if account.status == .archived {
                Text("Archived")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EditableAccount: Identifiable {
    let account: Account

    var id: AccountID {
        account.id
    }
}

#Preview {
    NavigationStack {
        AccountListView()
            .environmentObject(AppState(repository: AccountListPreviewRepository()))
    }
}

private struct AccountListPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}

private extension Sequence where Element == Account {
    func sortedForDisplay() -> [Account] {
        sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }

            if $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }
}
