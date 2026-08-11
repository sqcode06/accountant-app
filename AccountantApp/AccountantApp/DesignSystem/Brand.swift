import SwiftUI

/// The product's durable identity, kept separate from its working title.
///
/// `Accountant` still describes the build while naming work is unresolved. The
/// promise, voice, and mark can become familiar now without scattering a
/// provisional name through the interface.
enum Brand {
    static let productName = "Accountant"
    static let positioning = "Flexible budgets. Honest records."
    static let promise = "Record now. Review later."
    static let idea = "A soft routine with a hard record."
}

/// Two entries: one captured, one confirmed.
///
/// The mark encodes the product loop rather than the accounting engine. Everything
/// in this category signals *balance* — scales, equals signs, mirrored halves — but
/// balance is what the ledger does, not what the app is for. What this app actually
/// does is let you record carelessly now and settle it later, so the mark is the
/// same form twice in its two states: ghosted for captured, solid for confirmed.
///
/// The slant is time. Two level bars would read as an equals sign, which is the
/// generic answer for anything financial; slanting them turns a static comparison
/// into a sequence.
///
/// Colours come from the theme's `brandGround`/`brandInk`, which are the exact
/// values the app icon is generated from — so the mark on screen and the icon on
/// the home screen are the same artwork rather than cousins. An earlier version
/// hardcoded one brand palette and stroked bezier curves, which rendered as a
/// chunky X and sat as a cobalt square inside an orange interface.
struct BrandMark: View {
    var size: CGFloat = 64

    /// Draws the two bars without the tile behind them, for placing on a surface
    /// that already has its own background.
    var isBare: Bool = false

    var body: some View {
        ZStack {
            if !isBare {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(Theme.brandGround)
            }

            BrandBar(top: BrandBar.capturedTop)
                .fill(Theme.brandInk)
                .opacity(0.45)

            BrandBar(top: BrandBar.confirmedTop)
                .fill(Theme.brandInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One slanted bar, in coordinates normalised against the 1024pt icon artwork.
private struct BrandBar: Shape {
    /// Normalised y of the bar's top edge.
    let top: CGFloat

    static let capturedTop: CGFloat = 380.0 / 1024
    static let confirmedTop: CGFloat = 546.0 / 1024

    private let left: CGFloat = 212.0 / 1024
    private let right: CGFloat = 836.0 / 1024
    private let slant: CGFloat = 114.0 / 1024
    private let height: CGFloat = 106.0 / 1024

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: point(left + slant, top))
        path.addLine(to: point(right, top))
        path.addLine(to: point(right - slant, top + height))
        path.addLine(to: point(left, top + height))
        path.closeSubpath()

        return path
    }
}

/// A compact lockup for places where the product should sign its work without
/// turning the screen into an advertisement.
struct BrandSignature: View {
    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            BrandMark(size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.productName)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)

                Text(Brand.positioning)
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Brand.productName). \(Brand.positioning)")
    }
}

#Preview("Brand mark") {
    VStack(spacing: Metrics.Space.xl) {
        HStack(spacing: Metrics.Space.l) {
            BrandMark(size: 96)
            BrandMark(size: 60)
            BrandMark(size: 40)
        }

        BrandSignature()
    }
    .padding(Metrics.Space.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas)
}
