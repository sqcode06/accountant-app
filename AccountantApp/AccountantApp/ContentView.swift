import SwiftUI
import AccountantCore

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            loadedTab(title: "Summary") {
                DashboardView()
            }
            .tabItem {
                Label("Summary", systemImage: "chart.pie.fill")
            }

            loadedTab(title: "Transactions") {
                TransactionListView()
            }
            .tabItem {
                Label("Transactions", systemImage: "list.bullet.rectangle.portrait.fill")
            }

            loadedTab(title: "Import") {
                ImportPreviewScreen()
            }
            .tabItem {
                Label("Import", systemImage: "tray.and.arrow.down.fill")
            }

            loadedTab(title: "Reconcile") {
                ReconciliationView()
            }
            .tabItem {
                Label("Reconcile", systemImage: "checkmark.seal.fill")
            }

            loadedTab(title: "Accounts") {
                AccountListView()
            }
            .tabItem {
                Label("Accounts", systemImage: "tray.full.fill")
            }
        }
        .alert(item: $appState.lastError) { error in
            Alert(
                title: Text("Accountant"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func loadedTab<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            Group {
                if appState.isLoading {
                    ProgressView("Loading ledger...")
                } else {
                    content()
                }
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(
            AppState(repository: PreviewLedgerRepository())
        )
}

private struct PreviewLedgerRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}
