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

    @State private var isPresentingCapture = false

    var body: some View {
        TabView {
            tab(title: "Overview", systemImage: "square.grid.2x2") {
                OverviewView()
            }

            tab(title: "Budget", systemImage: "chart.bar") {
                BudgetView()
            }

            tab(title: "Activity", systemImage: "list.bullet") {
                ActivityView()
            }

            tab(title: "Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isPresentingCapture) {
            QuickEntryView()
                .environmentObject(appState)
        }
        .alert(item: $appState.lastError) { error in
            Alert(
                title: Text("Something went wrong"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
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
}

private struct PreviewLedgerRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger { Ledger() }
    func save(_ ledger: Ledger) async throws {}
}
