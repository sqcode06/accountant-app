import SwiftUI
import AccountantCore

/// Reconcile one account against a statement, by ticking entries off.
///
/// Replaces the old Reconcile tab, which could only ever say "you disagree with
/// your bank by €42" and offered no way to find out why. With per-posting cleared
/// state the screen can do the real job: show what has not been confirmed yet, let
/// you tick each one, and count down to zero.
///
/// Lives inside an account because that is where you already are when a statement
/// is in front of you.
struct AccountReconcileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appClock) private var clock

    let accountID: AccountID

    @State private var statementText = ""
    @FocusState private var isStatementFieldFocused: Bool

    /// `nil` until the user picks a date of their own.
    ///
    /// The picker's binding falls back to `clock.now()` while this stays `nil`, so
    /// a deterministic UI-test clock sees a fixed default date and a real device
    /// keeps tracking "today" — until the user actually chooses a date, at which
    /// point their choice sticks rather than drifting with the clock underneath them.
    @State private var chosenAsOf: Date?

    var body: some View {
        let report = self.report

        return Group {
            if let account {
                content(account, report: report)
            } else {
                ContentUnavailableView(
                    "Account unavailable",
                    systemImage: "questionmark.folder",
                    description: Text("This account is no longer in the ledger.")
                )
            }
        }
        .navigationTitle("Reconcile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ account: Account, report: ReconciliationReport?) -> some View {
        List {
            Section {
                statementCard(report)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } footer: {
                Text("Drafts stay out until you confirm them in Review. They still appear in account activity and balance. Ticking an entry marks it as cleared for this account; it moves no money.")
            }

            if let report {
                if report.uncleared.isEmpty {
                    Section {
                        if report.clearedDifference.amount == .zero {
                            Text("Your statement balance matches the total you have ticked off.")
                                .font(.uiCaption)
                                .foregroundStyle(Theme.inkMuted)
                        } else {
                            Text("No entries with an outstanding amount are listed for this date. Check the statement balance and date, and look for missing or incorrect entries.")
                                .font(.uiCaption)
                                .foregroundStyle(Theme.pending)
                                .accessibilityIdentifier("reconcile.uncheckedMismatch")
                        }
                    }
                } else {
                    Section {
                        ForEach(report.uncleared, id: \.transactionID) { entry in
                            UnclearedRow(entry: entry) {
                                Task {
                                    await appState.setCleared(
                                        true,
                                        forAccount: accountID,
                                        in: entry.transactionID
                                    )
                                }
                            }
                        }
                    } header: {
                        Text("Not yet on a statement")
                    } footer: {
                        Text("Tick only entries you find on your statement. A zero difference means the balances match; check the individual entries too.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func statementCard(_ report: ReconciliationReport?) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                Text("Statement balance")
                    .fieldLabel()

                TextField("0.00", text: $statementText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.figurePrimary)
                    .foregroundStyle(Theme.ink)
                    .focused($isStatementFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { isStatementFieldFocused = false }
                    .accessibilityIdentifier("reconcile.statementField")
            }

            DatePicker("As of", selection: asOfBinding, displayedComponents: .date)
                .font(.uiCaption)
                .accessibilityIdentifier("reconcile.datePicker")

            if let report {
                Hairline()

                HStack {
                    figureColumn(
                        label: "On statement",
                        money: report.clearedBalance,
                        role: .plain,
                        identifier: "reconcile.confirmed"
                    )

                    figureColumn(
                        label: "Difference",
                        money: report.clearedDifference,
                        role: report.clearedDifference.amount == .zero ? .plain : .balance,
                        alignment: .trailing,
                        identifier: "reconcile.difference"
                    )
                }

                if report.clearedDifference.amount == .zero {
                    Label("Balance matches", systemImage: "checkmark.circle.fill")
                        .font(.uiLabel)
                        .foregroundStyle(Theme.cleared)
                        .accessibilityIdentifier("reconcile.reconciledBadge")
                }
            }
        }
        .heroCard()
        .padding(.vertical, Metrics.Space.s)
    }

    /// Mirrors `FigureBlock`'s layout, rather than using it directly, so the
    /// rendered money `Text` — the thing a UI test actually needs to read — can
    /// carry its own accessibility identifier as a real leaf element.
    private func figureColumn(
        label: String,
        money: Money,
        role: MoneyText.Role,
        alignment: HorizontalAlignment = .leading,
        identifier: String
    ) -> some View {
        VStack(alignment: alignment, spacing: Metrics.Space.xs) {
            Text(label)
                .fieldLabel()

            MoneyText(money: money, role: role, font: .figureRow)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    // MARK: - Derived

    private var account: Account? {
        appState.ledger.accounts[accountID]
    }

    /// Built once per render.
    ///
    /// `reconcileAccount` makes two full passes over the ledger — one to total the
    /// balance, one to walk the sorted transactions — and both the list and the
    /// header card needed it, so it ran twice for every keystroke in the statement
    /// balance field.
    private var report: ReconciliationReport? {
        guard let account, let statementAmount else { return nil }

        return try? appState.ledger.reconcileAccount(
            accountID,
            statementBalance: Money(statementAmount, currency: appState.currency(for: account)),
            asOf: ReconciliationDate.endOfDay(effectiveAsOf)
        )
    }

    private var statementAmount: Decimal? {
        DecimalParsing.decimal(from: statementText)
    }

    /// Uses the app clock until the user picks a date of their own.
    private var effectiveAsOf: Date {
        chosenAsOf ?? clock.now()
    }

    private var asOfBinding: Binding<Date> {
        Binding(
            get: { effectiveAsOf },
            set: { chosenAsOf = $0 }
        )
    }
}

private struct UnclearedRow: View {
    let entry: UnclearedEntry
    let onTick: () -> Void

    var body: some View {
        Button(action: onTick) {
            HStack(spacing: Metrics.Space.m) {
                Image(systemName: "circle")
                    .foregroundStyle(Theme.inkFaint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.memo?.isEmpty == false ? entry.memo! : "Transaction")
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Text(DateDisplay.transactionDate(entry.date))
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: Metrics.Space.s)

                MoneyText(
                    money: entry.delta,
                    role: entry.delta.amount > .zero ? .inflow : .outflow,
                    showsPositiveSign: true
                )
            }
            .padding(.vertical, Metrics.Space.xs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reconcile.uncleared.\(entry.transactionID.rawValue.uuidString)")
    }
}
