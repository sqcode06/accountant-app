import SwiftUI
import AccountantCore

/// Four tabs, down from five.
///
/// The old set mirrored the core package's folder layout — Summary, Transactions,
/// Import, Reconcile, Accounts — which meant two occasional chores held permanent
/// places. Import is a thing you do when a statement arrives; Reconcile is a thing
/// you do inside one account. Neither is somewhere you live.
///
/// What replaced them earns its place: Budget is the reason the app exists, and
/// Activity is where the record lives.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var onboarding: OnboardingController

    @State private var isPresentingCapture = false
    @State private var isPresentingOnboarding = false

    /// Held here, above the theme rebuild, so switching theme leaves you on the
    /// tab you were already looking at.
    @State private var selectedTab = Tab.overview

    private enum Tab: Hashable {
        case overview, budget, activity, settings
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.isDataLocked {
                DataRecoveryBanner()
                    .environmentObject(appState)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            tabs
        }
        .animation(.snappy(duration: 0.25), value: appState.isDataLocked)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            tab(title: "Overview", systemImage: "square.grid.2x2") {
                OverviewView()
            }
            .tag(Tab.overview)

            tab(title: "Budget", systemImage: "chart.bar") {
                BudgetView()
            }
            .tag(Tab.budget)

            tab(title: "Activity", systemImage: "list.bullet") {
                ActivityView()
            }
            .tag(Tab.activity)

            tab(title: "Settings", systemImage: "gearshape") {
                SettingsView()
            }
            .tag(Tab.settings)
        }
        .tint(Theme.accent)
        // A theme only defines an appearance override when it has a palette for
        // just one. Themes covering both leave the system setting alone.
        .preferredColorScheme(themeManager.forcedColorScheme)
        .sheet(isPresented: $isPresentingCapture) {
            QuickEntryView()
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $isPresentingOnboarding) {
            OnboardingView { isPresentingOnboarding = false }
                .environmentObject(appState)
                .environmentObject(onboarding)
        }
        // Read once, on launch. Reading the controller directly in the binding
        // would slam the guide shut the instant its status changed, before the
        // finishing work had a chance to run.
        .task {
            isPresentingOnboarding = onboarding.shouldPresent
        }
        .appErrorAlert()
    }

    /// Every tab carries the capture button. Recording a purchase is the single
    /// most frequent thing anyone does here, so it should never be more than one
    /// tap away regardless of where you happen to be.
    @ViewBuilder
    private func tab<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            Group {
                if appState.isLoading {
                    ProgressView()
                } else {
                    content()
                }
            }
            // Forces a real rebuild when the theme changes. `Theme` resolves
            // through a static, which SwiftUI's dependency tracking cannot see, so
            // without this the app keeps drawing the previous palette until
            // something unrelated happens to invalidate it.
            //
            // Deliberately inside the NavigationStack and below the tab item: an
            // `.id()` on the tab child itself would change the identity TabView
            // uses for selection and fight the `.tag` above.
            .id(themeManager.generation)
            .background(Theme.canvas)
            .overlay(alignment: .bottomTrailing) {
                if !appState.isLoading {
                    CaptureButton { isPresentingCapture = true }
                        .padding(Metrics.Space.l)
                }
            }
        }
        .tabItem {
            Label(title, systemImage: systemImage)
        }
    }
}

/// The one persistent action in the app.
private struct CaptureButton: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.inkInverse)
                .frame(width: 56, height: 56)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Record spending")
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(repository: PreviewLedgerRepository()))
        .environmentObject(ThemeManager())
        .environmentObject(OnboardingController())
        .environmentObject(AppIconManager())
}

private struct PreviewLedgerRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger { Ledger() }
    func save(_ ledger: Ledger) async throws {}
}
