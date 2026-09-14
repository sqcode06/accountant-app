import SwiftUI

/// Spacing, radii, elevation.
enum Metrics {

    /// Generous. Tight radii read utilitarian; these read like a product someone
    /// paid for. Cards and sheets share `card` so nothing looks accidentally off.
    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 14
        static let inset: CGFloat = 10
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24

        /// Air around a hero figure. Generous quiet is most of what makes a layout
        /// feel expensive.
        static let hero: CGFloat = 28
    }
}

/// A hairline divider.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The standard card.
    ///
    /// On light it lifts with a soft shadow; on dark it lifts by being *lighter*
    /// than the canvas, because shadows on dark backgrounds just go muddy.
    func card(padding: CGFloat = Metrics.Space.l) -> some View {
        modifier(CardStyle(padding: padding, emphasized: false))
    }

    /// The hero card — one per screen at most. Carries a wash of the accent so the
    /// screen has a single clear focal point.
    func heroCard(padding: CGFloat = Metrics.Space.xl) -> some View {
        modifier(CardStyle(padding: padding, emphasized: true))
    }
}

private struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    emphasized ? Theme.accent.opacity(0.18) : Theme.hairline,
                    lineWidth: 0.5
                )
            }
            .shadow(
                color: shadowColor,
                radius: emphasized ? 18 : 10,
                y: emphasized ? 8 : 4
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
    }

    private var fill: Color {
        emphasized ? Theme.accentWash : Theme.surface
    }

    /// Dark mode gets no shadow at all — elevation there comes from the lighter
    /// surface colour instead.
    private var shadowColor: Color {
        guard colorScheme == .light else { return .clear }
        return Color.black.opacity(emphasized ? 0.08 : 0.05)
    }
}
