import SwiftUI

/// Spacing and corner radius scales.
///
/// The previous layer used seven corner radii (28, 24, 22, 20, 18, 16, 14) chosen
/// per-file, which reads as visual noise rather than hierarchy. Three steps is
/// enough: a card, something inset inside a card, and a pill.
enum Metrics {

    enum Radius {
        static let card: CGFloat = 20
        static let inset: CGFloat = 12
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

extension View {
    /// The single card treatment for the app.
    ///
    /// One elevation level, one radius, one hairline. Cards do not nest inside
    /// other cards — if content needs separating inside a card, use a divider or
    /// `Theme.surfaceInset`, not another card.
    func card(padding: CGFloat = Metrics.Space.l) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
    }
}
