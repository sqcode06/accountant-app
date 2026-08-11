import SwiftUI

@main
struct AccountantAppApp: App {
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(
            wrappedValue: AppState(
                repository: LocalJSONLedgerRepository.live(),
                classificationRuleRepository: LocalJSONClassificationRuleRepository.live(),
                budgetRepository: LocalJSONBudgetRepository.live()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.loadIfNeeded()
                }
        }
    }
}
