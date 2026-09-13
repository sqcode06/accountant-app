import Foundation
import AccountantCore

/// Presentation and the safe category-edit target share this interpretation.
/// New imports identify the purchase/income and fee separately. Old simple
/// entries remain editable; an unlabelled split must never be guessed at.
struct DraftReviewDetails {
    let transaction: AccountantCore.Transaction
    let accounts: [AccountID: Account]

    var categoryPostingIndex: Int? {
        let marked = transaction.postings.indices.filter {
            transaction.postings[$0].role == .counterparty
        }
        if !marked.isEmpty {
            guard marked.count == 1, isCategory(transaction.postings[marked[0]]) else { return nil }
            return marked[0]
        }
        guard transaction.postings.allSatisfy({ $0.role == nil }) else { return nil }
        let candidates = transaction.postings.indices.filter {
            let posting = transaction.postings[$0]
            return posting.role == nil && isCategory(posting)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    var categoryPosting: Posting? {
        categoryPostingIndex.map { transaction.postings[$0] }
    }

    var categoryName: String {
        if let posting = categoryPosting { return accounts[posting.accountID]?.name ?? "Unknown category" }
        let count = transaction.postings.filter(isCategory).count
        return count > 0 ? "Multiple categories" : "Transfer"
    }

    var title: String {
        let memo = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return memo.isEmpty ? categoryName : memo
    }

    /// Statement-line amount before a separately displayed fee. Negative means
    /// spending, positive means income or a refund, regardless of category kind.
    var amount: Money? {
        if let posting = categoryPosting {
            return Money(-posting.money.amount, currency: posting.money.currency)
        }
        return statementPosting?.money
    }

    var feePostings: [Posting] { transaction.postings.filter { $0.role == .fee } }

    var statementPosting: Posting? {
        let marked = transaction.postings.filter { $0.role == .statement }
        if marked.count == 1 { return marked[0] }
        let balances = transaction.postings.filter {
            let kind = accounts[$0.accountID]?.kind
            return kind == .asset || kind == .liability
        }
        if balances.count == 1 { return balances[0] }
        return balances.first { $0.money.amount < .zero }
    }

    var sourceName: String? {
        statementPosting.flatMap { accounts[$0.accountID]?.name }
    }

    var cannotRecategorizeReason: String? {
        guard categoryPostingIndex == nil else { return nil }
        return transaction.postings.contains(where: isCategory)
            ? "This split entry has multiple categories. They cannot be changed together here."
            : "Transfers move money between accounts and have no spending or income category."
    }

    private func isCategory(_ posting: Posting) -> Bool {
        let kind = accounts[posting.accountID]?.kind
        return kind == .expense || kind == .income
    }
}
