import SwiftUI

/// Semantic colour access for the whole app.
///
/// Views never name a palette or an appearance — they ask for `Theme.canvas` and
/// get whatever the selected theme says the canvas is, in whatever appearance is
/// currently on screen. That indirection is why adding a theme touches no screen.
///
/// Each property is *computed*, not stored, and hands back a `Color` backed by a
/// dynamic `UIColor`. The closure runs at draw time, so a colour resolves against
/// both the live theme and the live appearance rather than whatever was true when
/// the view was first built.
enum Theme {

    /// The active theme. Set through `ThemeManager`, never directly.
    static var current: AppTheme = ThemeCatalog.default

    // MARK: - Surfaces

    static var canvas: Color { color(\.canvas) }
    static var surface: Color { color(\.surface) }
    static var surfaceRaised: Color { color(\.surfaceRaised) }
    static var surfaceSunken: Color { color(\.surfaceSunken) }

    // MARK: - Ink

    static var ink: Color { color(\.ink) }
    static var inkMuted: Color { color(\.inkMuted) }
    static var inkFaint: Color { color(\.inkFaint) }
    static var inkInverse: Color { color(\.inkInverse) }

    // MARK: - Lines

    static var hairline: Color { color(\.hairline) }

    // MARK: - Accent

    static var accent: Color { color(\.accent) }
    static var accentWash: Color { color(\.accentWash) }

    // MARK: - Money

    static var inflow: Color { color(\.inflow) }

    /// A balance genuinely in deficit. Never ordinary spending — colouring every
    /// expense red turns a normal month into a wall of alarm.
    static var deficit: Color { color(\.deficit) }

    // MARK: - State

    /// Confirmed against a statement. Shares the inflow colour deliberately:
    /// both mean "this has settled".
    static var cleared: Color { color(\.inflow) }

    /// Recorded, not yet seen on a statement.
    static var pending: Color { color(\.pending) }

    // MARK: - Resolution

    private static func color(_ slot: KeyPath<ThemePalette, UInt32>) -> Color {
        Color(
            UIColor { traits in
                UIColor(rgb: current.palette(for: traits.userInterfaceStyle)[keyPath: slot])
            }
        )
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
