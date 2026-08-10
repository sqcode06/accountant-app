import SwiftUI
import AccountantCore

/// The one place money is rendered.
///
/// Previously `MoneyDisplay.string` returned a bare string and every caller
/// invented its own treatment: `TransactionRowView` had a private `amountPrefix`
/// and tint, the dashboard had neither, and nothing agreed on when to show a sign.
struct MoneyText: View {

    enum Role {
        /// A balance. Negative reads as a deficit; positive reads plain.
        case balance

        /// Money arriving. The only thing that gets green.
        case inflow

        /// Money leaving.
        ///
        /// Deliberately *not* coloured. Spending is the ordinary case in a
        /// budgeting app, and painting every expense red turns a normal month into
        /// a wall of alarm. Red is reserved for something actually wrong.
        case outflow

        /// No semantic colour at all.
        case plain
    }

    let money: Money
    var role: Role = .plain
    var font: Font = .amountRow

    /// Forces an explicit `+` on positive values. Useful in statement lines where
    /// direction matters more than magnitude.
    var showsPositiveSign: Bool = false

    var body: some View {
        Text(formatted)
            .font(font)
            .foregroundStyle(color)
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
            money.amount < .zero ? Theme.deficit : .primary
        case .inflow:
            Theme.inflow
        case .outflow, .plain:
            .primary
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

#Preview {
    VStack(alignment: .trailing, spacing: Metrics.Space.m) {
        MoneyText(
            money: Money(Decimal(1234.56), currency: Currency("EUR")),
            role: .balance,
            font: .amountHero
        )
        MoneyText(
            money: Money(Decimal(-89.10), currency: Currency("EUR")),
            role: .balance,
            font: .amountHero
        )
        MoneyText(
            money: Money(Decimal(42), currency: Currency("EUR")),
            role: .inflow,
            showsPositiveSign: true
        )
        MoneyText(
            money: Money(Decimal(-42), currency: Currency("EUR")),
            role: .outflow
        )
    }
    .padding()
}
