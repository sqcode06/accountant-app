import SwiftUI

/// Palette and surfaces.
///
/// Direction: modern premium consumer fintech. Sleek, high contrast, confident
/// with space. Depth on dark comes from *layering* — surfaces get lighter as they
/// come forward — rather than from shadows, which go muddy on dark backgrounds.
///
/// Colours are explicit hex with hand-tuned values for each appearance rather than
/// system semantic colours. System colours are correct but anonymous; they make
/// every app look like Settings. Dark mode here is designed, not inverted.
///
/// The accent is a small system rather than one shouting colour: cobalt carries
/// brand and interaction, mint and amber carry meaning about money. Deliberately
/// not the near-black-plus-one-acid-green look that every fintech template ships.
enum Theme {

    // MARK: - Surfaces (light → forward on dark)

    /// The page behind everything.
    static let canvas = Color.adaptive(light: 0xF4F5F7, dark: 0x0B0D10)

    /// A card or grouped row.
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x16191F)

    /// A surface sitting above another — a sheet, a highlighted card.
    static let surfaceRaised = Color.adaptive(light: 0xFFFFFF, dark: 0x1E222A)

    /// A region inset into a surface: a field, a well.
    static let surfaceSunken = Color.adaptive(light: 0xEEEFF2, dark: 0x101317)

    // MARK: - Ink

    static let ink = Color.adaptive(light: 0x0B0D10, dark: 0xF4F6F8)
    static let inkMuted = Color.adaptive(light: 0x6E7683, dark: 0x8B93A1)
    static let inkFaint = Color.adaptive(light: 0x9AA1AC, dark: 0x656C78)

    /// Ink on top of an accent-filled surface.
    static let inkInverse = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)

    // MARK: - Lines

    static let hairline = Color.adaptive(light: 0xE6E8EC, dark: 0x252A32)

    // MARK: - Accent

    /// Cobalt. Brand and interaction — the active tab, the primary button, a
    /// selected state. Never used to colour data.
    static let accent = Color.adaptive(light: 0x2F5FF0, dark: 0x5B85FF)

    /// A wash of the accent, for selected rows and the hero card.
    static let accentWash = Color.adaptive(light: 0xE8EEFF, dark: 0x1B2436)

    // MARK: - Money

    /// Money arriving.
    static let inflow = Color.adaptive(light: 0x0FA47A, dark: 0x34D9A4)

    /// A balance genuinely in deficit. Never ordinary spending — colouring every
    /// expense red turns a normal month into a wall of alarm.
    static let deficit = Color.adaptive(light: 0xE0443E, dark: 0xFF6B63)

    // MARK: - State

    /// Confirmed against a statement.
    static let cleared = Color.adaptive(light: 0x0FA47A, dark: 0x34D9A4)

    /// Recorded, not yet seen on a statement.
    static let pending = Color.adaptive(light: 0xC77A0A, dark: 0xF0A741)
}

// MARK: - Adaptive colour

private extension Color {
    /// Builds a colour with an explicit value for each appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
