import SwiftUI
import AccountantCore

/// Amount held as minor units, so entry needs no decimal point.
///
/// Typing 5, 0, 0 gives 5.00. This is how every fast-entry till and payment app
/// works, and it removes the single slowest moment in the old form — hunting for
/// the decimal key and deciding whether "5" meant five euros or five cents.
struct AmountEntry: Equatable {
    private(set) var minorUnits: Int = 0

    /// Two decimal places is right for every currency this app currently offers.
    ///
    /// Kept as exact `Decimal` arithmetic — no `Double` anywhere near money, even
    /// for something this small.
    var decimalValue: Decimal {
        Decimal(minorUnits) / 100
    }

    var isEmpty: Bool { minorUnits == 0 }

    mutating func append(_ digit: Int) {
        // Cap well below Int overflow; nobody is entering a trillion euros.
        guard minorUnits < 1_000_000_000 else { return }
        minorUnits = minorUnits * 10 + digit
    }

    mutating func deleteLast() {
        minorUnits /= 10
    }

    mutating func clear() {
        minorUnits = 0
    }

    func money(in currency: Currency) -> Money {
        Money(decimalValue, currency: currency)
    }
}

/// A numeric pad sized for one-handed use.
///
/// A custom pad rather than a `TextField` with `.decimalPad`: the system keyboard
/// animates in, steals half the screen, and puts the category picker below the
/// fold. Here the amount and the categories are visible at the same time, which is
/// what makes the whole capture two gestures.
struct AmountKeypad: View {
    @Binding var entry: AmountEntry

    var body: some View {
        VStack(spacing: Metrics.Space.s) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: Metrics.Space.s) {
                    ForEach(row, id: \.self) { key in
                        KeypadButton(key: key) { press(key) }
                    }
                }
            }
        }
    }

    private var rows: [[KeypadKey]] {
        [
            [.digit(1), .digit(2), .digit(3)],
            [.digit(4), .digit(5), .digit(6)],
            [.digit(7), .digit(8), .digit(9)],
            [.clear, .digit(0), .delete]
        ]
    }

    private func press(_ key: KeypadKey) {
        switch key {
        case let .digit(value):
            entry.append(value)
        case .delete:
            entry.deleteLast()
        case .clear:
            entry.clear()
        }
    }
}

enum KeypadKey: Hashable {
    case digit(Int)
    case delete
    case clear

    var label: String {
        switch self {
        case let .digit(value): String(value)
        case .delete: "delete.left"
        case .clear: "C"
        }
    }

    var isSymbol: Bool {
        if case .delete = self { return true }
        return false
    }

    var accessibilityName: String {
        switch self {
        case let .digit(value): String(value)
        case .delete: "Delete"
        case .clear: "Clear"
        }
    }
}

private struct KeypadButton: View {
    let key: KeypadKey
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Group {
                if key.isSymbol {
                    Image(systemName: key.label)
                        .font(.system(.title3, weight: .medium))
                } else {
                    Text(key.label)
                        .font(.system(.title2, weight: .medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Theme.surfaceSunken.opacity(isPressed ? 1 : 0),
                in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibilityName)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}

#Preview {
    struct Harness: View {
        @State private var entry = AmountEntry()

        var body: some View {
            VStack(spacing: Metrics.Space.xl) {
                MoneyText(
                    money: entry.money(in: Currency("EUR")),
                    role: .plain,
                    font: .figureHero
                )

                AmountKeypad(entry: $entry)
            }
            .padding(Metrics.Space.l)
            .background(Theme.canvas)
        }
    }

    return Harness()
}
