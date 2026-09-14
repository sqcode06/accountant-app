import SwiftUI
import AccountantCore

/// Everything that has been recorded, newest first.
///
/// Leads with the review queue when there is one. Entries captured in a hurry are
/// only useful once they have been checked, and a prompt at the top of the list is
/// the cheapest possible reminder — no notification permission required.
struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    @State private var searchText = ""

    /// The filtered list is built once and threaded down.
    ///
    /// `transactions` sorts the entire ledger and `drafts` sorts it again; between
    /// the two of them and `groupedByDay` calling back into `transactions`, drawing
    /// this screen once cost five full sorts of every transaction on file.
    var body: some View {
        let transactions = self.transactions
        let draftCount = appState.draftCount

        return Group {
            if transactions.isEmpty && draftCount == 0 {
                emptyState
            } else {
                content(transactions, draftCount: draftCount)
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $searchText, prompt: "Search memos")
        // Deleting from the transaction detail screen pops back to here, so this
        // is where that undo has to appear.
        .draftDeletionUndoBar()
    }

    private func content(
        _ transactions: [AccountantCore.Transaction],
        draftCount: Int
    ) -> some View {
        List {
            if draftCount > 0 && searchText.isEmpty {
                Section {
                    NavigationLink {
                        ReviewView()
                            .environmentObject(appState)
                    } label: {
                        ReviewPrompt(count: draftCount)
                    }
                }
            }

            ForEach(groupedByDay(transactions), id: \.day) { group in
                Section {
                    ForEach(group.transactions, id: \.id) { transaction in
                        NavigationLink {
                            TransactionDetailView(transactionID: transaction.id)
                                .environmentObject(appState)
                        } label: {
                            ActivityRow(
                                transaction: transaction,
                                accounts: appState.ledger.accounts
                            )
                        }
                    }
                } header: {
                    Text(group.day)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing recorded yet", systemImage: "list.bullet")
        } description: {
            Text("Tap the plus button to record what you spent. It takes two taps and you can fix the details later.")
        }
    }

    // MARK: - Derived

    private var transactions: [AccountantCore.Transaction] {
        let all = appState.ledger.allTransactionsSorted(includeDrafts: true).reversed()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !query.isEmpty else { return Array(all) }

        return all.filter { transaction in
            if (transaction.memo ?? "").lowercased().contains(query) { return true }

            return transaction.postings.contains { posting in
                (appState.ledger.accounts[posting.accountID]?.name ?? "")
                    .lowercased()
                    .contains(query)
            }
        }
    }

    /// Day headers give a long list rhythm and make "when did I buy that" answerable
    /// by scrolling rather than searching.
    private func groupedByDay(
        _ transactions: [AccountantCore.Transaction]
    ) -> [(day: String, transactions: [AccountantCore.Transaction])] {
        var order: [String] = []
        var buckets: [String: [AccountantCore.Transaction]] = [:]

        for transaction in transactions {
            let key = DateDisplay.transactionDate(transaction.date)

            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }

            buckets[key]?.append(transaction)
        }

        return order.map { (day: $0, transactions: buckets[$0] ?? []) }
    }
}

// MARK: - Review prompt

private struct ReviewPrompt: View {
    let count: Int

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            Image(systemName: "tray.full")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 entry to review" : "\(count) entries to review")
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)

                Text("Check what you captured, then confirm")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.vertical, Metrics.Space.xs)
    }
}

// MARK: - Row

private struct ActivityRow: View {
    let transaction: AccountantCore.Transaction
    let accounts: [AccountID: Account]

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                HStack(spacing: Metrics.Space.xs) {
                    Text(subtitle)
                        .lineLimit(1)

                    if transaction.state == .draft {
                        Text("· Unconfirmed")
                            .foregroundStyle(Theme.pending)
                    }
                }
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: Metrics.Space.s)

            if let amount {
                MoneyText(
                    money: amount,
                    role: amount.amount > .zero ? .inflow : .outflow,
                    showsPositiveSign: true
                )
            }
        }
        .padding(.vertical, Metrics.Space.xs)
    }

    /// Prefers the memo, then the category, then a plain description of direction.
    private var title: String {
        let memo = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !memo.isEmpty { return memo }

        if let category = categoryPosting.flatMap({ accounts[$0.accountID]?.name }) {
            return category
        }

        return (amount?.amount ?? 0) > .zero ? "Money in" : "Money out"
    }

    private var subtitle: String {
        transaction.postings
            .compactMap { accounts[$0.accountID] }
            .filter { $0.kind == .asset || $0.kind == .liability }
            .map(\.name)
            .joined(separator: " → ")
    }

    private var categoryPosting: Posting? {
        transaction.postings.first {
            let kind = accounts[$0.accountID]?.kind
            return kind == .expense || kind == .income
        }
    }

    /// Signed from the perspective of the money you hold: negative when it left.
    private var amount: Money? {
        let balancePosting = transaction.postings.first {
            let kind = accounts[$0.accountID]?.kind
            return kind == .asset || kind == .liability
        }

        guard let posting = balancePosting ?? transaction.postings.first else { return nil }

        return posting.money
    }
}
