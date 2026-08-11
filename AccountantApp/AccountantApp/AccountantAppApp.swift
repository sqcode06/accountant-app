import SwiftUI

@main
struct AccountantAppApp: App {
    @StateObject private var appState: AppState
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var onboarding = OnboardingController()
    @StateObject private var iconManager = AppIconManager()

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
                .environmentObject(onboarding)
                .environmentObject(iconManager)
                .task {
                    await appState.loadIfNeeded()
                }
        }
    }
}
