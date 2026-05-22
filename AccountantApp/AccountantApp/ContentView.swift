import SwiftUI
import AccountantCore

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    private let displayCurrency = Currency("EUR")

    var body: some View {
        VStack(spacing: 16) {
            Text("Accountant")
                .font(.largeTitle.bold())

            if appState.isLoading {
                ProgressView("Loading ledger...")
            } else {
                Text("Local ledger connected")
                    .foregroundStyle(.secondary)

                Text(accountSummaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Add demo account") {
                    Task {
                        await appState.createAccount(
                            name: nextDemoAccountName,
                            kind: .asset
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .alert(item: $appState.lastError) { error in
            Alert(
                title: Text("Accountant"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var accountSummaryText: String {
        let summaries = appState.ledger.accountBalanceSummaries(
            currency: displayCurrency,
            asOf: Date()
        )

        return "Accounts: \(summaries.count)"
    }

    private var nextDemoAccountName: String {
        "Demo Account \(appState.ledger.accounts.count + 1)"
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
