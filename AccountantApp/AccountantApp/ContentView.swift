import SwiftUI
import AccountantCore

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if appState.isLoading {
                        ProgressView("Loading ledger...")
                    } else {
                        DashboardView()
                    }
                }
                .navigationTitle("Summary")
            }
            .tabItem {
                Label("Summary", systemImage: "chart.pie.fill")
            }

            NavigationStack {
                Group {
                    if appState.isLoading {
                        ProgressView("Loading ledger...")
                    } else {
                        AccountListView()
                    }
                }
                .navigationTitle("Accounts")
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
