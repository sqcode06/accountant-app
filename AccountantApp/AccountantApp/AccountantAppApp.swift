import SwiftUI

@main
struct AccountantAppApp: App {
    @StateObject private var appState: AppState
    @StateObject private var themeManager = ThemeManager()

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
                .environmentObject(themeManager)
                .task {
                    await appState.loadIfNeeded()
                }
        }
    }
}
