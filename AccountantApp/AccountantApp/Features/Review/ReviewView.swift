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

            Section("Captured") {
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

            HStack(spacing: Metrics.Space.xl) {
                ForEach(totalsByCurrency(drafts), id: \.currency.code) { total in
                    FigureBlock(
                        label: "Total \(total.currency.code)",
                        money: total,
                        role: .outflow,
                        font: .figurePrimary
                    )
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
            .filter { $0.status == .active && $0.kind == .expense }
            .sortedForDisplay()
    }

    /// Grouped by currency — no implicit conversion, here or anywhere.
    private func totalsByCurrency(_ drafts: [AccountantCore.Transaction]) -> [Money] {
        var totals: [String: (currency: Currency, amount: Decimal)] = [:]

        for transaction in drafts {
            for posting in transaction.postings
            where appState.ledger.accounts[posting.accountID]?.kind == .expense {
                let code = posting.money.currency.code
                let running = totals[code]?.amount ?? .zero
                totals[code] = (posting.money.currency, running + posting.money.amount)
            }
        }

        return totals
            .values
            .sorted { $0.currency.code < $1.currency.code }
            .map { Money($0.amount, currency: $0.currency) }
    }
}

// MARK: - Row

private struct DraftRow: View {
    let transaction: AccountantCore.Transaction
    let accounts: [AccountID: Account]
    let categories: [Account]
    let onRecategorize: (Account) -> Void

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                // The category is the thing most likely to be wrong after a hurried
                // capture, so it is the tappable part of the row.
                Menu {
                    ForEach(categories, id: \.id) { category in
                        Button(category.name) { onRecategorize(category) }
                    }
                } label: {
                    HStack(spacing: Metrics.Space.xs) {
                        Text(categoryName ?? "Uncategorised")
                            .font(.uiRowTitle)
                            .foregroundStyle(Theme.ink)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                .disabled(categories.isEmpty)

                Text(subtitle)
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: Metrics.Space.s)

            if let amount {
                MoneyText(money: amount, role: .outflow)
            }
        }
        .padding(.vertical, Metrics.Space.xs)
    }

    private var categoryPosting: Posting? {
        transaction.postings.first { accounts[$0.accountID]?.kind == .expense }
    }

    private var categoryName: String? {
        categoryPosting.flatMap { accounts[$0.accountID]?.name }
    }

    private var amount: Money? {
        guard let posting = categoryPosting else { return nil }
        let magnitude = posting.money.amount < .zero ? -posting.money.amount : posting.money.amount
        return Money(-magnitude, currency: posting.money.currency)
    }

    private var subtitle: String {
        let source = transaction.postings
            .first { accounts[$0.accountID]?.kind != .expense }
            .flatMap { accounts[$0.accountID]?.name }

        let date = DateDisplay.transactionDate(transaction.date)

        guard let source else { return date }
        return "\(date) · \(source)"
    }
}
