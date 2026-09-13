import SwiftUI

@main
struct AccountantAppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appState: AppState
    @StateObject private var themeManager: ThemeManager
    @StateObject private var onboarding: OnboardingController
    @StateObject private var iconManager: AppIconManager
    @StateObject private var reminders: ReviewReminderController

    private let clock: AppClock

    init() {
        #if DEBUG
        if let fixture = AppUITestFixture.current() {
            _appState = StateObject(
                wrappedValue: AppState(
                    repository: fixture.ledgerRepository,
                    classificationRuleRepository: fixture.classificationRuleRepository,
                    budgetRepository: fixture.budgetRepository
                )
            )
            _themeManager = StateObject(wrappedValue: ThemeManager(defaults: fixture.defaults))
            _onboarding = StateObject(wrappedValue: OnboardingController(defaults: fixture.defaults))
            _iconManager = StateObject(wrappedValue: AppIconManager())
            _reminders = StateObject(wrappedValue: ReviewReminderController(defaults: fixture.defaults))
            clock = fixture.clock
            return
        }
        #endif

        _appState = StateObject(
            wrappedValue: AppState(
                repository: LocalJSONLedgerRepository.live(),
                classificationRuleRepository: LocalJSONClassificationRuleRepository.live(),
                budgetRepository: LocalJSONBudgetRepository.live()
            )
        )
        _themeManager = StateObject(wrappedValue: ThemeManager())
        _onboarding = StateObject(wrappedValue: OnboardingController())
        _iconManager = StateObject(wrappedValue: AppIconManager())
        _reminders = StateObject(wrappedValue: ReviewReminderController())
        clock = .live
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(onboarding)
                .environmentObject(iconManager)
                .environmentObject(reminders)
                .environment(\.appClock, clock)
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
