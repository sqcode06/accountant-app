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

    /// Brand colours do not follow the selected app theme. A Moss or Ember
    /// interface should still be recognisable as the same product on launch.
    enum Palette {
        static let cobalt = Color(red: 47.0 / 255.0, green: 95.0 / 255.0, blue: 240.0 / 255.0)
        static let paper = Color(red: 247.0 / 255.0, green: 246.0 / 255.0, blue: 243.0 / 255.0)
        static let settledMint = Color(red: 52.0 / 255.0, green: 217.0 / 255.0, blue: 164.0 / 255.0)
    }
}

/// Two balanced ribbons: one action recorded twice, and a captured entry that
/// later settles. The open centre keeps the symbol quiet and leaves it legible at
/// app-icon size.
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Brand.Palette.cobalt)

            RibbonGlyph()
                .padding(size * 0.19)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

private struct RibbonGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let lineWidth = proxy.size.width * 0.22

            ZStack {
                Ribbon(mirrored: false)
                    .stroke(
                        Brand.Palette.paper,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
                    )

                Ribbon(mirrored: true)
                    .stroke(
                        Brand.Palette.paper,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
                    )

                Ribbon(mirrored: true)
                    .stroke(
                        Brand.Palette.settledMint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
                    )
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: proxy.size.height * 0.49)
                    }
            }
        }
    }
}

private struct Ribbon: Shape {
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + (mirrored ? 1 - x : x) * rect.width,
                y: rect.minY + y * rect.height
            )
        }

        var path = Path()
        path.move(to: point(0.17, 0.10))
        path.addCurve(
            to: point(0.40, 0.34),
            control1: point(0.27, 0.18),
            control2: point(0.40, 0.20)
        )
        path.addCurve(
            to: point(0.40, 0.55),
            control1: point(0.45, 0.40),
            control2: point(0.45, 0.49)
        )
        path.addCurve(
            to: point(0.17, 0.90),
            control1: point(0.40, 0.69),
            control2: point(0.27, 0.81)
        )
        return path
    }
}

#Preview("Brand mark") {
    VStack(spacing: Metrics.Space.xl) {
        BrandMark(size: 96)
        BrandSignature()
    }
    .padding()
    .background(Theme.canvas)
}
