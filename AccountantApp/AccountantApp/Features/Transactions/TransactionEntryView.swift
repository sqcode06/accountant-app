import SwiftUI
import AccountantCore

/// The full editor: expense, income or transfer, with both sides chosen by hand.
///
/// Quick capture handles the common case in two gestures; this is the screen for
/// everything else — income, moving money between accounts, backdating, or naming
/// a category the strip does not show.
///
/// Two save actions rather than one, because the draft/confirmed split is the whole
/// point of the app. "Save for review" puts it in the evening queue; "Save & confirm"
/// is for when you are already certain and do not want to see it again.
struct TransactionEntryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKind: TransactionEntryKind = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var memo = ""
    @State private var primaryAccountID: AccountID?
    @State private var counterpartAccountID: AccountID?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.l) {
                    kindCard
                    amountCard
                    accountCard
                    detailCard
                    readinessHint
                    actionButtons
                }
                .padding(Metrics.Space.l)
            }
            .background(Theme.canvas)
            .navigationTitle("New transaction")
            .appErrorAlert()
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

    // MARK: - Type

    /// The type switcher doubles as the card header. A separate header card would
    /// have restated the selected type immediately above the control that sets it.
    private var kindCard: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(spacing: Metrics.Space.xs) {
                ForEach(TransactionEntryKind.allCases) { kind in
                    KindTab(
                        title: kind.title,
                        isSelected: kind == selectedKind
                    ) {
                        selectedKind = kind
                    }
                }
            }
            .padding(Metrics.Space.xs)
            .background(
                Theme.surfaceSunken,
                in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
            )

            Label(selectedKind.summary, systemImage: selectedKind.systemImageName)
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
        }
        .card()
    }

    // MARK: - Amount

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.s) {
            HStack {
                Text("Amount")
                    .fieldLabel()

                Spacer()

                Text(entryCurrency.code)
                    .fieldLabel(Theme.accent)
                    .padding(.horizontal, Metrics.Space.s)
                    .padding(.vertical, Metrics.Space.xs)
                    .background(Theme.accentWash, in: Capsule())
            }

            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .font(.figureHero)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .card()
    }

    // MARK: - Accounts

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
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
        .card()
    }

    private func accountPicker(
        title: String,
        accounts: [Account],
        selection: Binding<AccountID?>
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.s) {
            Text(title)
                .fieldLabel()

            Menu {
                Picker(title, selection: selection) {
                    Text("Select account").tag(AccountID?.none)

                    ForEach(accounts, id: \.id) { account in
                        Text("\(account.name) · \(account.kind.displayName)")
                            .tag(Optional(account.id))
                    }
                }
            } label: {
                HStack(spacing: Metrics.Space.s) {
                    Text(name(of: selection.wrappedValue, in: accounts) ?? "Select account")
                        .font(.uiRowTitle)
                        .foregroundStyle(selection.wrappedValue == nil ? Theme.inkFaint : Theme.ink)
                        .lineLimit(1)

                    Spacer(minLength: Metrics.Space.s)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.horizontal, Metrics.Space.m)
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Theme.surfaceSunken,
                    in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                )
            }
            .disabled(accounts.isEmpty)
        }
    }

    // MARK: - Details

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            HStack {
                Text("Date")
                    .fieldLabel()

                Spacer()

                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.accent)
            }

            VStack(alignment: .leading, spacing: Metrics.Space.s) {
                Text("Memo")
                    .fieldLabel()

                TextField(selectedKind.memoPlaceholder, text: $memo)
                    .textInputAutocapitalization(.sentences)
                    .font(.uiBody)
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accent)
                    .padding(.horizontal, Metrics.Space.m)
                    .frame(height: 44)
                    .background(
                        Theme.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                    )
            }
        }
        .card()
    }

    // MARK: - Readiness

    /// A hint, not a card. It appears and disappears as fields are filled, and
    /// giving it card weight made the layout jump every time it did.
    @ViewBuilder
    private var readinessHint: some View {
        if let readinessMessage {
            Label(readinessMessage, systemImage: "info.circle")
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.Space.xs)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: Metrics.Space.s) {
            Button {
                Task { await save(finalize: true) }
            } label: {
                HStack(spacing: Metrics.Space.s) {
                    if isSaving {
                        ProgressView().tint(Theme.inkInverse)
                    } else {
                        Image(systemName: "checkmark")
                    }

                    Text("Save & confirm")
                }
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
            .disabled(!isReadyToSave || isSaving)
            .opacity(isReadyToSave && !isSaving ? 1 : 0.4)

            Button {
                Task { await save(finalize: false) }
            } label: {
                Text("Save for review")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Theme.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isReadyToSave || isSaving)
            .opacity(isReadyToSave && !isSaving ? 1 : 0.4)
        }
        .animation(.easeOut(duration: 0.15), value: isReadyToSave)
    }

    // MARK: - Derived state

    private func name(of id: AccountID?, in accounts: [Account]) -> String? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }?.name
    }

    /// The currency of the account the money moves through.
    ///
    /// Previously hardcoded to EUR. Once the ledger began rejecting postings whose
    /// currency does not match the account's, that literal made this screen unable
    /// to record anything against a non-EUR account at all — and the failure was
    /// invisible, because the only alert in the app sat underneath this sheet.
    private var entryCurrency: Currency {
        guard
            let primaryAccountID,
            let account = appState.ledger.accounts[primaryAccountID]
        else {
            return appState.displayCurrency
        }

        return appState.currency(for: account)
    }

    /// The counterpart's declared currency, when it has one. Categories do not.
    private var counterpartCurrency: Currency? {
        guard
            let counterpartAccountID,
            let account = appState.ledger.accounts[counterpartAccountID]
        else {
            return nil
        }

        return account.currency
    }

    private var primaryAccounts: [Account] {
        activeAccounts(matching: selectedKind.primaryAccountKinds)
    }

    private var counterpartAccounts: [Account] {
        activeAccounts(matching: selectedKind.counterpartAccountKinds)
    }

    /// Parsed by the same code that reads bank statements.
    ///
    /// The old hand-rolled version swapped commas for dots and handed the result to
    /// `Decimal(string:)`, which reads "EUR" and "--" as zero rather than failing.
    /// That was masked here by the `> 0` check below, but only by luck.
    private var enteredAmount: Decimal? {
        DecimalParsing.decimal(from: amountText)
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

        // Both sides of a transfer hold balances, so both may declare a currency.
        // There is no conversion anywhere in this app, so a mismatch cannot be
        // recorded — say so here rather than letting the save fail.
        if let counterpartCurrency, counterpartCurrency != entryCurrency {
            return "Both accounts must use \(entryCurrency.code). Transfers between currencies need an explicit conversion."
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

    // MARK: - Save

    private func save(finalize: Bool) async {
        guard
            let amount = parsedAmount,
            let primaryAccountID,
            let counterpartAccountID
        else {
            return
        }

        isSaving = true
        defer { isSaving = false }

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

// MARK: - Type switcher

/// A themed segmented control.
///
/// `.pickerStyle(.segmented)` is a `UISegmentedControl`, and its track fill and
/// unselected text colour come from UIKit rather than from the palette — so on any
/// theme but the default it visibly did not belong to the screen behind it. The
/// only way to move those is a global `UISegmentedControl.appearance()`, which
/// fights the runtime theme switch.
private struct KindTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(isSelected ? Theme.inkInverse : Theme.inkMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Metrics.Radius.inset, style: .continuous)
                            .fill(Theme.accent)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isSelected)
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
