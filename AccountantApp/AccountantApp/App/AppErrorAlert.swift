import SwiftUI

/// Presents `AppState.lastError` from whichever layer is currently on top.
///
/// The app had exactly one alert, attached to the `TabView`. SwiftUI will not
/// present an alert on a view that is covered by a `.sheet` or
/// `.fullScreenCover` — and nearly every write in this app happens inside one:
/// quick capture, the full editor, the account editor, the budget editor, import,
/// onboarding. So a failed save set `lastError`, nothing appeared, and the button
/// simply looked dead.
///
/// Attaching this to each presented root means the error surfaces wherever the
/// user actually is. `AppError` already maps core errors to human copy; the
/// problem was never the message, only that nobody ever saw it.
struct AppErrorAlert: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content.alert(item: $appState.lastError) { error in
            Alert(
                title: Text("Couldn't save"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

extension View {
    /// Surfaces save failures at this layer. Apply to the root of every sheet and
    /// full-screen cover that can write.
    func appErrorAlert() -> some View {
        modifier(AppErrorAlert())
    }
}
