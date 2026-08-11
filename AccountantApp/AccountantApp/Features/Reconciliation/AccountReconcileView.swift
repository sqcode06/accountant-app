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

    let accountID: AccountID

    @State private var statementText = ""
    @State private var asOf = Date()

    var body: some View {
        Group {
            if let account {
                content(account)
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

    private func content(_ account: Account) -> some View {
        List {
            Section {
                statementCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let report {
                if report.uncleared.isEmpty {
                    Section {
                        Text("Everything is confirmed against a statement.")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkMuted)
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
                        Text("Tick each entry as you find it on your statement. When the difference reaches zero, the account is reconciled.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var statementCard: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                Text("Statement balance")
                    .fieldLabel()

                TextField("0.00", text: $statementText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.figurePrimary)
                    .foregroundStyle(Theme.ink)
            }

            DatePicker("As of", selection: $asOf, displayedComponents: .date)
                .font(.uiCaption)

            if let report {
                Hairline()

                HStack {
                    FigureBlock(
                        label: "Confirmed",
                        money: report.clearedBalance,
                        role: .plain,
                        font: .figureRow
                    )

                    FigureBlock(
                        label: "Difference",
                        money: report.clearedDifference,
                        role: report.clearedDifference.amount == .zero ? .plain : .balance,
                        font: .figureRow,
                        alignment: .trailing
                    )
                }

                if report.clearedDifference.amount == .zero {
                    Label("Reconciled", systemImage: "checkmark.circle.fill")
                        .font(.uiLabel)
                        .foregroundStyle(Theme.cleared)
                }
            }
        }
        .heroCard()
        .padding(.vertical, Metrics.Space.s)
    }

    // MARK: - Derived

    private var account: Account? {
        appState.ledger.accounts[accountID]
    }

    private var report: ReconciliationReport? {
        guard let account, let statementAmount else { return nil }

        return try? appState.ledger.reconcileAccount(
            accountID,
            statementBalance: Money(statementAmount, currency: appState.currency(for: account)),
            asOf: endOfDay(asOf)
        )
    }

    private var statementAmount: Decimal? {
        let normalised = statementText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard !normalised.isEmpty else { return nil }

        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func endOfDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)

        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
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
    }
}
