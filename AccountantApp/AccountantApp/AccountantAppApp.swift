import SwiftUI

@main
struct AccountantAppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appState: AppState
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var onboarding = OnboardingController()
    @StateObject private var iconManager = AppIconManager()
    @StateObject private var reminders = ReviewReminderController()

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
                .environmentObject(reminders)
                .task {
                    await appState.loadIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Writes are debounced, so leaving the app is the one moment where a
            // change could still be sitting in memory. Flushing here is what makes
            // the debounce safe.
            guard phase != .active else { return }
            Task { await appState.flushPendingWrites() }
        }
    }
}
