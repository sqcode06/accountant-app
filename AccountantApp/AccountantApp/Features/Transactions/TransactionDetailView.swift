import SwiftUI
import AccountantCore

/// One transaction, including the postings behind it.
///
/// The postings are shown rather than hidden. You know double-entry, and seeing
/// both sides is how you tell a miscategorised expense from a mis-keyed amount.
/// The two core methods that back editing here — `updateDraftTransaction` and
/// `deleteDraftTransaction` — existed from the start with nothing calling them.
struct TransactionDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let transactionID: TransactionID

    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let transaction {
                content(transaction)
            } else {
                ContentUnavailableView(
                    "Transaction unavailable",
                    systemImage: "questionmark.square.dashed",
                    description: Text("This transaction is no longer in the ledger.")
                )
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ transaction: AccountantCore.Transaction) -> some View {
        List {
            Section {
                header(transaction)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(Array(transaction.postings.enumerated()), id: \.offset) { _, posting in
                    PostingRow(
                        posting: posting,
                        account: appState.ledger.accounts[posting.accountID]
                    )
                }
            } header: {
                Text("Postings")
            } footer: {
                Text("Every transaction sums to zero. Money moves between accounts; it never appears or disappears.")
            }

            if transaction.state == .draft {
                Section {
                    Button {
                        Task {
                            if await appState.confirmTransactions(ids: [transaction.id]) {
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Confirm", systemImage: "checkmark")
                    }

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } footer: {
                    Text("Confirmed transactions become permanent records and can no longer be edited or deleted.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await appState.deleteDraftTransaction(id: transactionID) {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func header(_ transaction: AccountantCore.Transaction) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.s) {
            HStack {
                Text(transaction.state == .draft ? "Unconfirmed" : "Confirmed")
                    .fieldLabel(transaction.state == .draft ? Theme.pending : Theme.cleared)

                Spacer()

                Text(DateDisplay.transactionDate(transaction.date))
                    .fieldLabel()
            }

            if let memo = transaction.memo, !memo.isEmpty {
                Text(memo)
                    .font(.uiTitle)
                    .foregroundStyle(Theme.ink)
            }

            if let origin = transaction.origin {
                Text("Imported from \(origin.source)")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .card()
        .padding(.vertical, Metrics.Space.s)
    }

    private var transaction: AccountantCore.Transaction? {
        appState.ledger.transactions.first { $0.id == transactionID }
    }
}

private struct PostingRow: View {
    let posting: Posting
    let account: Account?

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account?.name ?? "Unknown account")
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)

                HStack(spacing: Metrics.Space.xs) {
                    Text(account?.kind.displayName ?? "—")

                    if posting.cleared {
                        Text("· Cleared")
                            .foregroundStyle(Theme.cleared)
                    }
                }
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: Metrics.Space.s)

            MoneyText(
                money: posting.money,
                role: posting.money.amount > .zero ? .inflow : .outflow,
                showsPositiveSign: true
            )
        }
        .padding(.vertical, Metrics.Space.xs)
    }
}
