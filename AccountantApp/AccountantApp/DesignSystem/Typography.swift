import SwiftUI

/// Type scale.
///
/// Every one of these is built from a Dynamic Type text style rather than a fixed
/// point size. The previous layer hardcoded `.system(size: 42)`, `size: 38` and
/// `size: 34` for its hero figures, which meant the most important numbers in the
/// app were the only text that refused to respond to the user's text size setting.
extension Font {

    /// The single large figure on a screen — an account balance, a net position.
    static let amountHero = Font.system(.largeTitle, design: .rounded, weight: .bold)
        .monospacedDigit()

    /// A secondary figure: a card total, a summary line.
    static let amountPrimary = Font.system(.title3, design: .rounded, weight: .semibold)
        .monospacedDigit()

    /// An amount inside a list row. Monospaced digits keep columns aligned.
    static let amountRow = Font.system(.callout, design: .rounded, weight: .medium)
        .monospacedDigit()

    /// A running balance trailing a statement line — present but recessive.
    static let amountSecondary = Font.system(.caption, design: .rounded)
        .monospacedDigit()
}
