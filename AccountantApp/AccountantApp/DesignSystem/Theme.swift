import SwiftUI

/// Semantic surfaces and colours for the whole app.
///
/// Screens should never reach for a raw colour. The previous layer had four
/// unrelated gradients (accent→purple, blue, green→cyan, and one more in import)
/// and hardcoded `.white.opacity(0.25)` strokes that disappeared in dark mode.
/// Everything here derives from system semantic colours, so light and dark are
/// correct without a second definition.
enum Theme {

    // MARK: - Surfaces

    /// The page behind everything.
    static let canvas = Color(.systemGroupedBackground)

    /// A card sitting on the canvas. One elevation level only — cards do not nest.
    static let surface = Color(.secondarySystemGroupedBackground)

    /// A region inside a card, when one is genuinely needed.
    static let surfaceInset = Color(.tertiarySystemGroupedBackground)

    /// Hairline separators and card borders.
    static let hairline = Color(.separator)

    // MARK: - Money

    /// Money arriving. Green is reserved for this and nothing else.
    static let inflow = Color(.systemGreen)

    /// A balance that is negative when it should not be — an overdrawn asset.
    /// Distinct from ordinary spending, which is not an error and is not coloured.
    static let deficit = Color(.systemRed)

    // MARK: - State

    /// Confirmed by the bank.
    static let cleared = Color(.systemGreen)

    /// Recorded but not yet seen on a statement.
    static let pending = Color(.systemOrange)

    // MARK: - Account kinds

    /// Tint for an account kind, used for icon chips.
    ///
    /// Deliberately muted: these identify a kind at a glance, they are not
    /// decoration, and six saturated hues in one list is noise.
    static func tint(for kind: AccountKindTint) -> Color {
        switch kind {
        case .asset: Color(.systemTeal)
        case .liability: Color(.systemPink)
        case .income: Color(.systemGreen)
        case .expense: Color(.systemIndigo)
        case .equity: Color(.systemGray)
        case .clearing: Color(.systemGray)
        }
    }
}

/// Mirrors `AccountKind` without importing the core into the theme layer.
enum AccountKindTint {
    case asset, liability, income, expense, equity, clearing
}
