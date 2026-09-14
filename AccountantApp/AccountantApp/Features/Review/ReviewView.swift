import SwiftUI
import AccountantCore

/// The evening half of the capture loop.
///
/// Quick capture is deliberately careless — it guesses the account and takes the
/// category you tapped, because stopping to be precise at a till is how people
/// give up on budgeting. This is where that carelessness gets paid off: see what
/// you recorded, fix the wrong ones, confirm the batch.
///
/// Confirmation is all-or-nothing, so a review either happened or it did not.
struct ReviewView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var reminders: ReviewReminderController

    @State private var isConfirming = false

    /// Drafts and categories are built once here.
    ///
    /// `drafts` sorts the whole ledger and was read seven times per render;
    /// `categories` filtered and sorted every account and was read *inside* the
    /// row loop, so it ran once per draft. Fifty drafts meant fifty sorts of the
    /// account list to draw one screen.
    var body: some View {
        let drafts = appState.draftTransactions

        return Group {
            if drafts.isEmpty {
                allClear
            } else {
                content(drafts)
            }
        }
        .navigationTitle("Review")
        .draftDeletionUndoBar()
    }

    // MARK: - Content

    private func content(_ drafts: [AccountantCore.Transaction]) -> some View {
        let categories = self.categories

        return List {
            Section {
                summary(drafts)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Entries") {
                ForEach(drafts, id: \.id) { transaction in
                    DraftRow(
                        transaction: transaction,
                        accounts: appState.ledger.accounts,
                        categories: categories,
                        onRecategorize: { category in
                            Task {
                                await appState.recategorizeDraft(
                                    id: transaction.id,
                                    to: category.id
                                )
                            }
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await appState.deleteDraftTransaction(id: transaction.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await appState.confirmTransactions(ids: [transaction.id]) }
                        } label: {
                            Label("Confirm", systemImage: "checkmark")
                        }
                        .tint(Theme.cleared)
                    }
                }
            }

            Section {
                confirmAllButton(drafts)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func summary(_ drafts: [AccountantCore.Transaction]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            Text(drafts.count == 1 ? "1 entry to review" : "\(drafts.count) entries to review")
                .font(.uiTitle)
                .foregroundStyle(Theme.ink)

            ForEach(totalsByCurrency(drafts), id: \.currency.code) { total in
                HStack(spacing: Metrics.Space.xl) {
                    FigureBlock(label: "Spending \(total.currency.code)",
                                money: Money(total.spending, currency: total.currency),
                                role: .outflow, font: .figurePrimary)
                    if total.income != .zero {
                        FigureBlock(label: "Income \(total.currency.code)",
                                    money: Money(total.income, currency: total.currency),
                                    role: .inflow, font: .figurePrimary)
                    }
                }
            }
        }
        .heroCard()
        .padding(.vertical, Metrics.Space.s)
    }

    private func confirmAllButton(_ drafts: [AccountantCore.Transaction]) -> some View {
        Button {
            confirmAll(drafts)
        } label: {
            HStack(spacing: Metrics.Space.s) {
                if isConfirming {
                    ProgressView().tint(Theme.inkInverse)
                } else {
                    Image(systemName: "checkmark")
                }

                Text(drafts.count == 1 ? "Confirm entry" : "Confirm all \(drafts.count)")
            }
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Theme.inkInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isConfirming)
        .padding(.vertical, Metrics.Space.s)
        .accessibilityIdentifier("review.confirmAll")
    }

    private var allClear: some View {
        ContentUnavailableView {
            Label("Nothing to review", systemImage: "checkmark.circle")
        } description: {
            Text("Everything you have recorded is confirmed. Anything captured from now on will land here.")
        }
    }

    // MARK: - Actions

    /// Confirms exactly the drafts that were on screen.
    ///
    /// Taking the rendered list rather than re-reading the ledger means the button
    /// does what its label promised: "Confirm all 5" confirms those five, even if a
    /// sixth arrived between the render and the tap.
    private func confirmAll(_ drafts: [AccountantCore.Transaction]) {
        isConfirming = true

        Task {
            let ids = drafts.map(\.id)
            let confirmed = await appState.confirmTransactions(ids: ids)

            isConfirming = false

            if confirmed {
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                // The one moment worth spending the single permission prompt iOS
                // allows: the review loop has just worked, so an offer to remind
                // them next time means something. Asking on first launch, before
                // the app has recorded anything, spends that one chance on a no.
                await reminders.offerAfterFirstReview()
            }
        }
    }

    // MARK: - Derived

    private var categories: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && ($0.kind == .expense || $0.kind == .income) }
            .sortedForDisplay()
    }

    /// Grouped by currency — no implicit conversion, here or anywhere.
    private func totalsByCurrency(_ drafts: [AccountantCore.Transaction]) -> [ReviewCurrencyTotals] {
        var totals: [String: ReviewCurrencyTotals] = [:]

        for transaction in drafts {
            for posting in transaction.postings {
                let kind = appState.ledger.accounts[posting.accountID]?.kind
                guard kind == .expense || kind == .income else { continue }
                let code = posting.money.currency.code
                var total = totals[code] ?? ReviewCurrencyTotals(currency: posting.money.currency)
                if kind == .expense { total.spending += posting.money.amount }
                if kind == .income { total.income -= posting.money.amount }
                totals[code] = total
            }
        }

        return totals
            .values
            .sorted { $0.currency.code < $1.currency.code }
    }
}

private struct ReviewCurrencyTotals {
    let currency: Currency
    var spending: Decimal = .zero
    var income: Decimal = .zero
}

// MARK: - Row

private struct DraftRow: View {
    let transaction: AccountantCore.Transaction
    let accounts: [AccountID: Account]
    let categories: [Account]
    let onRecategorize: (Account) -> Void

    private var details: DraftReviewDetails {
        DraftReviewDetails(transaction: transaction, accounts: accounts)
    }
    private var identifier: String { "review.row.\(transaction.id.rawValue.uuidString)" }

    var body: some View {
        let compatibleCategories = categories.filter { account in
            account.currency == nil || account.currency == details.amount?.currency
        }
        return VStack(alignment: .leading, spacing: Metrics.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(details.title)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("\(identifier).memo")
                Spacer(minLength: Metrics.Space.s)
                if let amount = details.amount {
                    MoneyText(money: amount, role: amount.amount > .zero ? .inflow : .outflow,
                              showsPositiveSign: true)
                        .accessibilityIdentifier("\(identifier).amount")
                }
            }

            if details.categoryPostingIndex != nil && !compatibleCategories.isEmpty {
                Menu {
                    ForEach(compatibleCategories, id: \.id) { category in
                        Button(category.name) { onRecategorize(category) }
                    }
                } label: {
                    Label(details.categoryName, systemImage: "chevron.down")
                        .font(.uiBody)
                }
                .accessibilityIdentifier("\(identifier).category")
            } else {
                Text(details.categoryName)
                    .font(.uiBody)
                    .accessibilityIdentifier("\(identifier).category")
                if let reason = details.cannotRecategorizeReason {
                    Text(reason).font(.uiCaption).foregroundStyle(Theme.inkMuted)
                } else {
                    Text("No active category supports this currency. Add one in Settings to change this entry.")
                        .font(.uiCaption).foregroundStyle(Theme.inkMuted)
                }
            }

            ForEach(Array(details.feePostings.enumerated()), id: \.offset) { _, posting in
                Text("Fee: \(MoneyDisplay.string(posting.money)) · \(accounts[posting.accountID]?.name ?? "Unknown category")")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityIdentifier("\(identifier).fee")
            }

            Text([DateDisplay.transactionDate(transaction.date), details.sourceName]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.vertical, Metrics.Space.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
