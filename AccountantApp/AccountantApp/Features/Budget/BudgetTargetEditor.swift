import SwiftUI
import AccountantCore

/// Sets or changes a category's monthly limit.
///
/// Reuses the capture keypad rather than a text field, so entering a number means
/// the same thing everywhere in the app.
struct BudgetTargetEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let category: Account
    let period: BudgetPeriod
    let currentAmount: Money?

    @State private var entry = AmountEntry()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: Metrics.Space.xs) {
                    MoneyText(
                        money: entry.money(in: currency),
                        role: .plain,
                        font: .figureHero
                    )
                    .opacity(entry.isEmpty ? 0.3 : 1)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: entry.minorUnits)

                    Text("a month on \(category.name)")
                        .fieldLabel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Metrics.Space.hero)

                Spacer(minLength: Metrics.Space.m)

                AmountKeypad(entry: $entry)
                    .padding(.horizontal, Metrics.Space.l)

                saveButton
                    .padding(Metrics.Space.l)
            }
            .background(Theme.canvas)
            .navigationTitle(currentAmount == nil ? "Set a limit" : "Change limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .appErrorAlert()
            .onAppear(perform: seedFromCurrentAmount)
        }
        .presentationDetents([.large])
    }

    private var saveButton: some View {
        VStack(spacing: Metrics.Space.s) {
            Button(action: save) {
                Text(isSaving ? "Saving…" : "Save limit")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.inkInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Theme.accent,
                        in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(entry.isEmpty || isSaving)
            .opacity(entry.isEmpty || isSaving ? 0.4 : 1)

            // Says which month it takes effect from, because changing a limit does
            // not silently rewrite the months already behind you.
            Text("Applies from \(monthTitle) onward. Earlier months keep the limit they had.")
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func seedFromCurrentAmount() {
        guard let currentAmount, entry.isEmpty else { return }

        let minorUnits = NSDecimalNumber(decimal: currentAmount.amount * 100).intValue

        for digit in String(max(0, minorUnits)) {
            if let value = digit.wholeNumberValue {
                entry.append(value)
            }
        }
    }

    private func save() {
        guard !entry.isEmpty else { return }

        isSaving = true

        Task {
            let saved = await appState.setBudgetTarget(
                amount: entry.money(in: currency),
                for: category.id,
                from: period
            )

            isSaving = false

            if saved { dismiss() }
        }
    }

    // MARK: - Derived

    private var currency: Currency {
        currentAmount?.currency ?? appState.displayCurrency
    }

    private var monthTitle: String {
        guard let date = period.dateInterval()?.start else { return "this month" }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
