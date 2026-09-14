import SwiftUI
import AccountantCore

/// Destructive actions, kept behind their own screen.
///
/// Separated from Settings rather than sitting at the bottom of it, because
/// scrolling past "Erase everything" on the way to something harmless is how
/// accidents happen. Each action states what survives it, not just what it
/// destroys — "delete all transactions" is a very different promise depending on
/// whether your accounts and budgets come back afterwards.
///
/// Nothing here is undoable. The confirmations say so plainly rather than asking
/// "are you sure?", which is a question nobody reads.
struct DangerZoneView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var onboarding: OnboardingController

    @State private var pendingAction: DangerAction?
    @State private var isWorking = false

    var body: some View {
        List {
            Section {
                row(.clearTransactions)
                row(.clearBudget)
                row(.removeUnusedAccounts)
            } header: {
                Text("Selective")
            } footer: {
                Text("Each of these leaves the rest of your setup intact.")
            }

            Section {
                row(.eraseEverything)
            } header: {
                Text("Start over")
            } footer: {
                Text("Erasing clears the app's current transactions, accounts, budgets and import rules. Existing backups and recovery files are kept. There is no undo.")
            }

            Section {
                count("Transactions", value: appState.ledger.transactions.count, key: "transactions")
                count("Accounts", value: appState.ledger.accounts.count, key: "accounts")
                count("Budget limits", value: appState.budget.targets.count, key: "budgets")
                count("Import rules", value: appState.classificationRules.count, key: "rules")
            } header: {
                Text("What is here now")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Danger zone")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .confirmationDialog(
            pendingAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmButtonTitle, role: .destructive) {
                perform(action)
            }
            .accessibilityIdentifier(action.confirmAccessibilityIdentifier)
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.consequence)
        }
    }

    private func row(_ action: DangerAction) -> some View {
        Button {
            pendingAction = action
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.uiRowTitle)
                    .foregroundStyle(action.isSevere ? Theme.deficit : Theme.ink)

                Text(action.subtitle)
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Metrics.Space.xs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }

    private func count(_ title: String, value: Int, key: String) -> some View {
        LabeledContent {
            Text("\(value)")
                .accessibilityIdentifier("danger.count.\(key)")
        } label: {
            Text(title)
        }
    }

    private func perform(_ action: DangerAction) {
        isWorking = true

        Task {
            switch action {
            case .clearTransactions:
                await appState.clearAllTransactions()
            case .clearBudget:
                await appState.clearBudget()
            case .removeUnusedAccounts:
                await appState.removeUnusedAccounts()
            case .eraseEverything:
                // Reset the guide too, so the app is genuinely in a first-run
                // state rather than empty with the setup step already spent.
                if await appState.eraseAllData() {
                    onboarding.reset()
                }
            }

            isWorking = false
            pendingAction = nil
        }
    }
}

enum DangerAction: Identifiable {
    case clearTransactions
    case clearBudget
    case removeUnusedAccounts
    case eraseEverything

    var id: String { title }

    var accessibilityIdentifier: String {
        switch self {
        case .clearTransactions: "danger.clearTransactions"
        case .clearBudget: "danger.clearBudget"
        case .removeUnusedAccounts: "danger.removeUnusedAccounts"
        case .eraseEverything: "danger.erase"
        }
    }

    var confirmAccessibilityIdentifier: String {
        switch self {
        case .clearTransactions: "danger.confirmClearTransactions"
        case .clearBudget: "danger.confirmClearBudget"
        case .removeUnusedAccounts: "danger.confirmRemoveUnusedAccounts"
        case .eraseEverything: "danger.confirmErase"
        }
    }

    var isSevere: Bool {
        self == .eraseEverything
    }

    var title: String {
        switch self {
        case .clearTransactions: "Delete all transactions"
        case .clearBudget: "Clear all budget limits"
        case .removeUnusedAccounts: "Remove unused accounts"
        case .eraseEverything: "Erase everything"
        }
    }

    var subtitle: String {
        switch self {
        case .clearTransactions:
            "Keeps your accounts, categories and budget limits."
        case .clearBudget:
            "Keeps every transaction. Only the monthly limits go."
        case .removeUnusedAccounts:
            "Only accounts that have never appeared in a transaction."
        case .eraseEverything:
            "Transactions, accounts, budgets and import rules."
        }
    }

    var confirmationTitle: String {
        switch self {
        case .clearTransactions: "Delete all transactions?"
        case .clearBudget: "Clear all budget limits?"
        case .removeUnusedAccounts: "Remove unused accounts?"
        case .eraseEverything: "Erase everything?"
        }
    }

    /// States what actually happens, including what survives.
    var consequence: String {
        switch self {
        case .clearTransactions:
            "Every transaction is deleted, confirmed ones included. Accounts, categories and budget limits stay. This cannot be undone."
        case .clearBudget:
            "Every monthly limit is removed, for past months as well as this one. Transactions are untouched. This cannot be undone."
        case .removeUnusedAccounts:
            "Accounts with no history are deleted. Anything that has appeared in a transaction is kept, because deleting it would leave postings pointing at nothing."
        case .eraseEverything:
            "Your current transactions, accounts, budgets and import rules are cleared, and the setup guide runs again. Existing backups and recovery files are kept. This cannot be undone."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .clearTransactions: "Delete transactions"
        case .clearBudget: "Clear limits"
        case .removeUnusedAccounts: "Remove accounts"
        case .eraseEverything: "Erase everything"
        }
    }
}
