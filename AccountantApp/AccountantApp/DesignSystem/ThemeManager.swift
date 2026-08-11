import SwiftUI

/// Owns the theme selection and makes changes propagate.
///
/// Propagation is the whole problem. `Theme`'s colours resolve through a static,
/// so a change is invisible to SwiftUI's dependency tracking: nothing knows to
/// re-render, and the app keeps drawing the old palette until something unrelated
/// invalidates it.
///
/// The fix is `generation`, bumped on every change and used as an `.id()` on the
/// tab content in `ContentView`. That forces a genuine rebuild rather than relying
/// on diffing to notice colours it cannot see. Rebuilding is cheap here because
/// changing theme is a deliberate, rare act — and the selected tab is held
/// separately, so you stay where you were.
@MainActor
final class ThemeManager: ObservableObject {

    private static let storageKey = "selectedThemeID"

    @Published private(set) var theme: AppTheme

    /// Incremented on every change; drives the rebuild.
    @Published private(set) var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedID = defaults.string(forKey: Self.storageKey)
        let resolved = storedID.map(ThemeCatalog.theme(id:)) ?? ThemeCatalog.default

        self.theme = resolved
        Theme.current = resolved
    }

    private let defaults: UserDefaults

    func select(_ theme: AppTheme) {
        guard theme.id != self.theme.id else { return }

        self.theme = theme
        Theme.current = theme
        generation += 1

        defaults.set(theme.id, forKey: Self.storageKey)
    }

    /// Nil when the theme supports both appearances, in which case the system
    /// setting wins — a theme should not override that preference unless it has
    /// no palette for one of them.
    var forcedColorScheme: ColorScheme? {
        theme.forcedColorScheme
    }
}
