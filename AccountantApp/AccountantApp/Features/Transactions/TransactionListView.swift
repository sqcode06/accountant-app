import SwiftUI
import AccountantCore

struct TransactionListView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingEntry = false

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView {
                    Label("No transactions yet", systemImage: "receipt")
                } description: {
                    Text("Add an expense, income, or transfer to start turning accounts into a living budget.")
                } actions: {
                    Button {
                        isPresentingEntry = true
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(transactions, id: \.id) { transaction in
                            TransactionRowView(
                                transaction: transaction,
                                accounts: appState.ledger.accounts
                            ) {
                                Task {
                                    await appState.finalizeTransaction(id: transaction.id)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background {
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.10),
                            Color(.systemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingEntry = true
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingEntry) {
            TransactionEntryView()
                .environmentObject(appState)
        }
    }

    private var transactions: [AccountantCore.Transaction] {
        Array(appState.ledger.allTransactionsSorted(includeDrafts: true).reversed())
    }
}

#Preview {
    NavigationStack {
        TransactionListView()
            .environmentObject(AppState(repository: TransactionListPreviewRepository()))
    }
}

private struct TransactionListPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}
