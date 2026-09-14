import SwiftUI

/// Type scale.
///
/// Figures are the hero: large, bold, tightly tracked SF Pro with tabular digits.
/// That combination is what reads as modern premium fintech — confident numbers
/// with air around them. Rounded digits read friendly-but-cheap; serif digits read
/// old-world private bank. Neither is what this app is.
///
/// Everything is built from a Dynamic Type text style, so the largest text setting
/// still scales. Fixed point sizes would make the most important numbers in the app
/// the only text that ignores the user's preference.
extension Font {

    // MARK: - Figures

    /// The single large figure on a screen — a net position, an account balance.
    static let figureHero = Font.system(.largeTitle, weight: .bold)
        .monospacedDigit()

    /// A card total or section total.
    static let figurePrimary = Font.system(.title2, weight: .semibold)
        .monospacedDigit()

    /// An amount in a list row.
    static let figureRow = Font.system(.callout, weight: .semibold)
        .monospacedDigit()

    /// A running balance or secondary figure — present, recessive.
    static let figureTrailing = Font.system(.caption, weight: .medium)
        .monospacedDigit()

    // MARK: - Interface

    static let uiTitle = Font.system(.headline, weight: .semibold)
    static let uiBody = Font.system(.body, weight: .regular)
    static let uiRowTitle = Font.system(.body, weight: .medium)
    static let uiCaption = Font.system(.caption, weight: .regular)

    /// Small label above a figure or beside a control.
    static let uiLabel = Font.system(.caption, weight: .medium)
}

extension Text {
    /// Tightens tracking on large figures.
    ///
    /// Default tracking is tuned for prose. At display sizes it leaves numbers
    /// looking loose and unresolved; pulling it in is most of what separates a
    /// considered balance from a default one.
    func figureTracking() -> Text {
        self.tracking(-0.6)
    }
}

extension View {
    /// A small muted label. Sentence case on purpose — uppercase tracked eyebrows
    /// read editorial, which is a different product than this one.
    func fieldLabel(_ color: Color = Theme.inkMuted) -> some View {
        self
            .font(.uiLabel)
            .foregroundStyle(color)
    }
}
