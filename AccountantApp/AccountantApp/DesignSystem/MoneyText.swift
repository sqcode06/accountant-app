import SwiftUI
import AccountantCore

/// The one place money is rendered.
///
/// Owns the sign, the colour, the face and the alignment, so no screen reinvents
/// them. Figures are always trailing-aligned with tabular spacing: every amount on
/// a screen shares one right edge, and digits do not shift as values change. That
/// alignment does more to make the app feel considered than any amount of colour.
struct MoneyText: View {

    enum Role {
        /// A balance. Negative reads as a deficit; positive reads as plain ink.
        case balance

        /// Money arriving. The only thing that gets viridian.
        case inflow

        /// Money leaving. Deliberately uncoloured — spending is the ordinary case
        /// in a budgeting app, and painting all of it red is just alarm.
        case outflow

        /// No semantic colour.
        case plain
    }

    let money: Money
    var role: Role = .plain
    var font: Font = .figureRow

    /// Forces an explicit `+` on positive values, for statement lines where
    /// direction matters more than magnitude.
    var showsPositiveSign: Bool = false

    var body: some View {
        Text(formatted)
            .figureTracking()
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(accessibilityLabel)
    }

    private var formatted: String {
        let base = MoneyDisplay.string(money)

        guard showsPositiveSign, money.amount > .zero else {
            return base
        }

        return "+" + base
    }

    private var color: Color {
        switch role {
        case .balance:
            money.amount < .zero ? Theme.deficit : Theme.ink
        case .inflow:
            Theme.inflow
        case .outflow, .plain:
            Theme.ink
        }
    }

    private var accessibilityLabel: String {
        switch role {
        case .inflow:
            "\(formatted) in"
        case .outflow:
            "\(formatted) out"
        case .balance, .plain:
            formatted
        }
    }
}

/// A labelled figure: a small muted label with the amount beneath it.
struct FigureBlock: View {
    let label: String
    let money: Money
    var role: MoneyText.Role = .balance
    var font: Font = .figureHero
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: Metrics.Space.xs) {
            Text(label)
                .fieldLabel()

            MoneyText(money: money, role: role, font: font)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignment == .trailing ? .trailing : .leading
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Metrics.Space.xl) {
        FigureBlock(
            label: "Net position",
            money: Money(Decimal(12_480.55), currency: Currency("EUR"))
        )
        .heroCard()

        HStack(spacing: Metrics.Space.l) {
            FigureBlock(
                label: "In this month",
                money: Money(Decimal(2_400), currency: Currency("EUR")),
                role: .inflow,
                font: .figurePrimary
            )

            FigureBlock(
                label: "Out this month",
                money: Money(Decimal(1_180.20), currency: Currency("EUR")),
                role: .outflow,
                font: .figurePrimary
            )
        }
        .card()

        VStack(spacing: Metrics.Space.m) {
            HStack {
                Text("Bolt Food").font(.uiRowTitle)
                Spacer()
                MoneyText(
                    money: Money(Decimal(-8.40), currency: Currency("EUR")),
                    role: .outflow
                )
            }

            Hairline()

            HStack {
                Text("Salary").font(.uiRowTitle)
                Spacer()
                MoneyText(
                    money: Money(Decimal(2_400), currency: Currency("EUR")),
                    role: .inflow,
                    showsPositiveSign: true
                )
            }
        }
        .card()
    }
    .padding(Metrics.Space.l)
    .frame(maxHeight: .infinity)
    .background(Theme.canvas)
}
