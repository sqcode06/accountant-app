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
    @State private var validationMessage: String?

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .asset)
        case let .edit(account):
            _name = State(initialValue: account.name)
            _kind = State(initialValue: account.kind)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    Picker("Kind", selection: $kind) {
                        ForEach(AccountKindCatalog.all, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.systemImageName)
                                .tag(kind)
                        }
                    }
                    .disabled(isEditing)

                    if isEditing {
                        Text("Account kind is fixed for now. Create a new account if the bucket belongs to a different accounting category.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
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
            validationMessage = "Account name cannot be empty."
            return
        }

        validationMessage = nil

        Task {
            let didSave: Bool

            switch mode {
            case .create:
                didSave = await appState.createAccount(
                    name: cleanedName,
                    kind: kind
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
