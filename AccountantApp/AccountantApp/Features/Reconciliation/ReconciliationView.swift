import SwiftUI
import AccountantCore

struct ReconciliationView: View {
    @EnvironmentObject private var appState: AppState

    // Temporary until app settings / preferred display currency exist.
    private let displayCurrency = Currency("EUR")

    @State private var selectedAccountID: AccountID?
    @State private var statementBalanceText = ""
    @State private var asOfDate = Date()
    @State private var snapshot: ReconciliationSnapshot?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReconciliationHeroCard()

                if reconcilableAccounts.isEmpty {
                    ReconciliationEmptyCard()
                } else {
                    reconciliationForm
                    resultSection
                }
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.14),
                    Color.cyan.opacity(0.08),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear(perform: ensureDefaultSelection)
    }

    private var reconciliationForm: some View {
        ReconciliationPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Statement check")
                    .font(.headline)

                Picker("Account", selection: $selectedAccountID) {
                    Text("Select account").tag(AccountID?.none)
                    ForEach(reconcilableAccounts, id: \.id) { account in
                        Text(accountPickerTitle(account)).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedAccountID) { _, _ in
                    resetResult()
                }

                DatePicker("As of", selection: $asOfDate, displayedComponents: .date)
                    .onChange(of: asOfDate) { _, _ in
                        resetResult()
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Statement balance")
                        .font(.subheadline.weight(.semibold))

                    TextField("0.00", text: $statementBalanceText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: statementBalanceText) { _, _ in
                            resetResult()
                        }

                    Text("Compared in \(displayCurrency.code). Draft transactions are excluded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    buildSnapshot()
                } label: {
                    Label("Run reconciliation", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canReconcile)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let errorMessage {
            ReconciliationStatusCard(
                title: "Could not reconcile",
                message: errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }

        if let snapshot {
            ReconciliationResultCard(snapshot: snapshot)
        }
    }

    private var reconcilableAccounts: [Account] {
        appState.ledger.accounts.values
            .filter { account in
                account.status == .active && [.asset, .liability].contains(account.kind)
            }
            .sortedForDisplay()
    }

    private var canReconcile: Bool {
        selectedAccountID != nil && !statementBalanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func buildSnapshot() {
        ensureDefaultSelection()

        guard let selectedAccountID else {
            errorMessage = "Select an account to reconcile."
            snapshot = nil
            return
        }

        guard let statementBalance = parseAmount(statementBalanceText) else {
            errorMessage = "Enter a valid statement balance."
            snapshot = nil
            return
        }

        do {
            snapshot = try ReconciliationSnapshot.make(
                from: appState.ledger,
                accountID: selectedAccountID,
                statementBalance: statementBalance,
                currency: displayCurrency,
                asOf: asOfDate
            )
            errorMessage = nil
        } catch {
            errorMessage = AppError(error).message
            snapshot = nil
        }
    }

    private func ensureDefaultSelection() {
        if let selectedAccountID,
           reconcilableAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        selectedAccountID = reconcilableAccounts.first?.id
        resetResult()
    }

    private func resetResult() {
        snapshot = nil
        errorMessage = nil
    }

    private func parseAmount(_ text: String) -> Decimal? {
        let compact = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")

        guard !compact.isEmpty else { return nil }

        let normalized = normalizeDecimalText(compact)
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func normalizeDecimalText(_ text: String) -> String {
        let dotIndex = text.lastIndex(of: ".")
        let commaIndex = text.lastIndex(of: ",")

        if let dotIndex, let commaIndex {
            let decimalSeparator: Character = dotIndex > commaIndex ? "." : ","
            let groupingSeparator: Character = decimalSeparator == "." ? "," : "."

            return text
                .filter { $0 != groupingSeparator }
                .replacingOccurrences(of: String(decimalSeparator), with: ".")
        }

        if text.filter({ $0 == "," }).count > 1 {
            return text.replacingOccurrences(of: ",", with: "")
        }

        if text.filter({ $0 == "." }).count > 1 {
            return text.replacingOccurrences(of: ".", with: "")
        }

        if let separator = dotIndex ?? commaIndex {
            let fractionLength = text.distance(from: text.index(after: separator), to: text.endIndex)

            if fractionLength == 3 {
                return text.replacingOccurrences(of: String(text[separator]), with: "")
            }
        }

        return text.replacingOccurrences(of: ",", with: ".")
    }

    private func accountPickerTitle(_ account: Account) -> String {
        "\(account.name) · \(account.kind.displayName)"
    }
}

private struct ReconciliationHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Reconciliation", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Trust loop")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Text("Compare the ledger to reality")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)

            Text("Choose a statement account, enter the external balance, and check whether Accountant agrees as of that date.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
    }
}

private struct ReconciliationPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ReconciliationResultCard: View {
    let snapshot: ReconciliationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: snapshot.isMatched ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(statusTint)
                    .frame(width: 44, height: 44)
                    .background(statusTint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.statusTitle)
                        .font(.title2.bold())

                    Text(snapshot.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(spacing: 10) {
                ReconciliationAmountRow(
                    title: "Ledger balance",
                    amount: snapshot.report.ledgerBalance,
                    systemImage: "book.closed"
                )
                ReconciliationAmountRow(
                    title: "Statement balance",
                    amount: snapshot.report.statementBalance,
                    systemImage: "doc.text"
                )
                ReconciliationAmountRow(
                    title: "Difference",
                    amount: snapshot.report.difference,
                    systemImage: "minus.forwardslash.plus"
                )
            }

            Text("\(snapshot.account.name) · \(snapshot.account.kind.displayName) · finalized transactions only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(statusTint.opacity(0.35))
        }
    }

    private var statusTint: Color {
        snapshot.isMatched ? .green : .orange
    }
}

private struct ReconciliationAmountRow: View {
    let title: String
    let amount: Money
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(MoneyDisplay.string(amount))
                .font(.headline.monospacedDigit())
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReconciliationStatusCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ReconciliationEmptyCard: View {
    var body: some View {
        ContentUnavailableView(
            "No statement accounts yet",
            systemImage: "checkmark.seal",
            description: Text("Create an active asset or liability account first, then come back to reconcile it against an external statement.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ReconciliationView()
            .environmentObject(AppState(repository: ReconciliationPreviewRepository()))
    }
}

private struct ReconciliationPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}
