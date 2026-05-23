import SwiftUI
import AccountantCore

struct TransactionEntryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Temporary until app settings / preferred display currency exist.
    private let entryCurrency = Currency("EUR")

    @State private var selectedKind: TransactionEntryKind = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var memo = ""
    @State private var primaryAccountID: AccountID?
    @State private var counterpartAccountID: AccountID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    kindPickerCard
                    amountCard
                    accountCard
                    detailCard
                    readinessCard
                    actionButtons
                }
                .padding()
            }
            .background {
                LinearGradient(
                    colors: [
                        selectedKind.tint.opacity(0.16),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .navigationTitle("New transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                resetSelectionsForCurrentKind()
            }
            .onChange(of: selectedKind) { _, _ in
                resetSelectionsForCurrentKind()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(selectedKind.title, systemImage: selectedKind.systemImageName)
                .font(.headline)
                .foregroundStyle(selectedKind.tint)

            Text("Record a draft now, then finalize immediately if you are sure it is correct.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var kindPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type")
                .font(.headline)

            Picker("Type", selection: $selectedKind) {
                ForEach(TransactionEntryKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
        .transactionFormCard()
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Amount")
                    .font(.headline)

                Spacer()

                Text(entryCurrency.code)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .transactionFormCard()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accounts")
                .font(.headline)

            accountPicker(
                title: selectedKind.primaryAccountTitle,
                accounts: primaryAccounts,
                selection: $primaryAccountID
            )

            accountPicker(
                title: selectedKind.counterpartAccountTitle,
                accounts: counterpartAccounts,
                selection: $counterpartAccountID
            )
        }
        .transactionFormCard()
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.headline)

            DatePicker("Date", selection: $date, displayedComponents: .date)

            VStack(alignment: .leading, spacing: 8) {
                Text("Memo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(selectedKind.memoPlaceholder, text: $memo)
                    .textInputAutocapitalization(.sentences)
            }
        }
        .transactionFormCard()
    }

    @ViewBuilder
    private var readinessCard: some View {
        if let readinessMessage {
            Label(readinessMessage, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await save(finalize: false) }
            } label: {
                Label("Save Draft", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isReadyToSave)

            Button {
                Task { await save(finalize: true) }
            } label: {
                Label("Save & Finalize", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReadyToSave)
        }
    }

    private func accountPicker(
        title: String,
        accounts: [Account],
        selection: Binding<AccountID?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                Text("Select account").tag(AccountID?.none)

                ForEach(accounts, id: \.id) { account in
                    Text("\(account.name) · \(account.kind.displayName)")
                        .tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryAccounts: [Account] {
        activeAccounts(matching: selectedKind.primaryAccountKinds)
    }

    private var counterpartAccounts: [Account] {
        activeAccounts(matching: selectedKind.counterpartAccountKinds)
    }

    private var enteredAmount: Decimal? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        return Decimal(string: normalized)
    }

    private var parsedAmount: Decimal? {
        guard let amount = enteredAmount, amount > .zero else {
            return nil
        }

        return amount
    }

    private var memoForSave: String? {
        let cleaned = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private var readinessMessage: String? {
        if primaryAccounts.isEmpty || counterpartAccounts.isEmpty {
            return selectedKind.emptyRequirementMessage
        }

        if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a positive amount."
        }

        if enteredAmount == nil {
            return "Enter a valid amount."
        }

        if parsedAmount == nil {
            return "Amount must be greater than zero."
        }

        if primaryAccountID == nil {
            return "Choose \(selectedKind.primaryAccountTitle.lowercased())."
        }

        if counterpartAccountID == nil {
            return "Choose \(selectedKind.counterpartAccountTitle.lowercased())."
        }

        if selectedKind == .transfer, primaryAccountID == counterpartAccountID {
            return "Choose two different accounts for a transfer."
        }

        return nil
    }

    private var isReadyToSave: Bool {
        readinessMessage == nil
    }

    private func activeAccounts(matching kinds: [AccountKind]) -> [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && kinds.contains($0.kind) }
            .sortedForDisplay()
    }

    private func resetSelectionsForCurrentKind() {
        primaryAccountID = primaryAccounts.first?.id
        counterpartAccountID = counterpartAccounts.first?.id

        if selectedKind == .transfer, primaryAccountID == counterpartAccountID {
            counterpartAccountID = counterpartAccounts.dropFirst().first?.id
        }
    }

    private func save(finalize: Bool) async {
        guard
            let amount = parsedAmount,
            let primaryAccountID,
            let counterpartAccountID
        else {
            return
        }

        let money = Money(amount, currency: entryCurrency)
        let success: Bool

        switch selectedKind {
        case .expense:
            if finalize {
                success = await appState.createFinalizedExpense(
                    paidFrom: primaryAccountID,
                    category: counterpartAccountID,
                    amount: money,
                    date: date,
                    memo: memoForSave
                )
            } else {
                success = await appState.createDraftExpense(
                    paidFrom: primaryAccountID,
                    category: counterpartAccountID,
                    amount: money,
                    date: date,
                    memo: memoForSave
                )
            }
        case .income:
            if finalize {
                success = await appState.createFinalizedIncome(
                    receivedIn: primaryAccountID,
                    source: counterpartAccountID,
                    amount: money,
                    date: date,
                    memo: memoForSave
                )
            } else {
                success = await appState.createDraftIncome(
                    receivedIn: primaryAccountID,
                    source: counterpartAccountID,
                    amount: money,
                    date: date,
                    memo: memoForSave
                )
            }
        case .transfer:
            if finalize {
                success = await appState.createFinalizedTransfer(
                    from: primaryAccountID,
                    to: counterpartAccountID,
                    amount: money,
                    date: date,
                    memo: memoForSave
                )
            } else {
                success = await appState.createDraftTransfer(
                    from: primaryAccountID,
                    to: counterpartAccountID,
                    amount: money,
                    date: date,
                    memo: memoForSave
                )
            }
        }

        if success {
            dismiss()
        }
    }
}

private extension View {
    func transactionFormCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    TransactionEntryView()
        .environmentObject(AppState(repository: TransactionEntryPreviewRepository()))
}

private struct TransactionEntryPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        Ledger()
    }

    func save(_ ledger: Ledger) async throws {}
}
