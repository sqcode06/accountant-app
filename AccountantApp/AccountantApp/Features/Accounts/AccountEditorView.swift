import SwiftUI
import AccountantCore

struct AccountEditorView: View {
    enum Mode {
        case create
        case edit(Account)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private let mode: Mode

    @State private var name: String
    @State private var kind: AccountKind
    @State private var currency: Currency
    @State private var isShowingAdvancedKinds = false

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .asset)
            _currency = State(initialValue: Currency("EUR"))
        case let .edit(account):
            _name = State(initialValue: account.name)
            _kind = State(initialValue: account.kind)
            _currency = State(initialValue: account.currency ?? Currency("EUR"))
        }
    }

    /// Equity and Clearing are hidden until asked for.
    ///
    /// They are genuine account kinds, but "Equity" in a picker between "Income"
    /// and "Expense" reads as a thing you are supposed to understand. Anyone who
    /// needs them knows to look; nobody else should have to skip past them to add
    /// a bank account. An account that already *is* one of them still shows its
    /// own kind, or the editor would misreport what it is looking at.
    private var offeredKinds: [AccountKind] {
        if isShowingAdvancedKinds || AccountKindCatalog.isAdvanced(kind) {
            return AccountKindCatalog.all
        }

        return AccountKindCatalog.everyday
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    Picker("Kind", selection: $kind) {
                        ForEach(offeredKinds, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.systemImageName)
                                .tag(kind)
                        }
                    }
                    .disabled(isEditing)

                    Text(kind.plainDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !isEditing && !isShowingAdvancedKinds {
                        Button("Show accounting kinds") {
                            isShowingAdvancedKinds = true
                        }
                        .font(.footnote)
                    }

                    if isEditing {
                        Text("Account kind is fixed for now. Create a new account if the bucket belongs to a different accounting category.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if kind.isDenominated {
                        Picker("Currency", selection: $currency) {
                            ForEach(CurrencyCatalog.options(including: currency), id: \.code) { option in
                                Text(CurrencyCatalog.displayName(for: option)).tag(option)
                            }
                        }
                        .disabled(isEditing)
                    } else {
                        HStack {
                            Text("Currency")
                            Spacer()
                            Text("Any")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if kind.isDenominated {
                        Text(isEditing
                             ? "Currency is fixed once an account has been created, so existing amounts stay meaningful."
                             : "This account will only accept amounts in this currency. Anything else is rejected rather than quietly ignored.")
                    } else {
                        Text("Categories accept any currency. Groceries bought in euros and in dollars both belong here.")
                    }
                }

                if cleanedName.isEmpty {
                    Text("Account name is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if case let .edit(account) = mode {
                    Section("Status") {
                        HStack {
                            Text("Current status")
                            Spacer()
                            Text(account.status.displayName)
                                .foregroundStyle(.secondary)
                        }

                        if account.status == .active {
                            Button("Archive Account", role: .destructive) {
                                Task {
                                    if await appState.archiveAccount(id: account.id) {
                                        dismiss()
                                    }
                                }
                            }
                        } else {
                            Button("Restore Account") {
                                Task {
                                    if await appState.restoreAccount(id: account.id) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .appErrorAlert()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(cleanedName.isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .create:
            "New Account"
        case .edit:
            "Edit Account"
        }
    }

    private var isEditing: Bool {
        if case .edit = mode {
            true
        } else {
            false
        }
    }

    private var cleanedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !cleanedName.isEmpty else {
            return
        }
        
        Task {
            let didSave: Bool

            switch mode {
            case .create:
                didSave = await appState.createAccount(
                    name: cleanedName,
                    kind: kind,
                    currency: kind.isDenominated ? currency : nil
                )
            case let .edit(account):
                didSave = await appState.renameAccount(
                    id: account.id,
                    to: cleanedName
                )
            }

            if didSave {
                dismiss()
            }
        }
    }
}

#Preview("Create account") {
    AccountEditorView(mode: .create)
        .environmentObject(AppState(repository: AccountEditorPreviewRepository()))
}

private struct AccountEditorPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}
