import SwiftUI

/// Progress against a monthly limit.
///
/// Over-budget fills the track completely in the deficit colour rather than
/// overflowing or clipping silently: the bar's job is to make "past the limit"
/// unmissable at a glance, and a bar that looks 100% full either way would hide
/// exactly the state worth noticing.
struct BudgetBar: View {
    /// Fraction of the limit used. May exceed 1.
    let progress: Double
    var isOverspent: Bool = false

    /// Warn before the limit is actually hit — at four-fifths there is still time
    /// to change behaviour, which is the entire point of showing this.
    private var isNearLimit: Bool { progress >= 0.8 && !isOverspent }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceSunken)

                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(progress, 1)) * proxy.size.width)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.35), value: progress)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        if isOverspent { return Theme.deficit }
        if isNearLimit { return Theme.pending }
        return Theme.accent
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Metrics.Space.xl) {
        BudgetBar(progress: 0.39)
        BudgetBar(progress: 0.85)
        BudgetBar(progress: 1.12, isOverspent: true)
    }
    .padding(Metrics.Space.xl)
    .background(Theme.canvas)
}
