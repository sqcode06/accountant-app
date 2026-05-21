import Foundation

public enum TransactionCreationError: Error, Equatable, Sendable {
    case nonPositiveAmount(Money)
}

public extension Transaction {
    /// Creates a draft expense transaction.
    ///
    /// Accounting semantics:
    /// - the payment account decreases;
    /// - the expense/category account increases.
    static func draftExpense(
        paidFrom: AccountID,
        category: AccountID,
        amount: Money,
        date: Date = Date(),
        memo: String? = nil,
        origin: TransactionOrigin? = nil
    ) throws -> Transaction {
        try requirePositive(amount)

        return Transaction(
            date: date,
            memo: memo,
            postings: [
                Posting(accountID: paidFrom, money: Money(-amount.amount, currency: amount.currency)),
                Posting(accountID: category, money: amount)
            ],
            state: .draft,
            origin: origin
        )
    }

    /// Creates a draft income transaction.
    ///
    /// Accounting semantics:
    /// - the receiving account increases;
    /// - the income/source account decreases.
    static func draftIncome(
        receivedIn: AccountID,
        source: AccountID,
        amount: Money,
        date: Date = Date(),
        memo: String? = nil,
        origin: TransactionOrigin? = nil
    ) throws -> Transaction {
        try requirePositive(amount)

        return Transaction(
            date: date,
            memo: memo,
            postings: [
                Posting(accountID: receivedIn, money: amount),
                Posting(accountID: source, money: Money(-amount.amount, currency: amount.currency))
            ],
            state: .draft,
            origin: origin
        )
    }

    /// Creates a draft transfer transaction between two balance accounts.
    ///
    /// Accounting semantics:
    /// - the source account decreases;
    /// - the destination account increases.
    static func draftTransfer(
        from: AccountID,
        to: AccountID,
        amount: Money,
        date: Date = Date(),
        memo: String? = nil,
        origin: TransactionOrigin? = nil
    ) throws -> Transaction {
        try requirePositive(amount)

        return Transaction(
            date: date,
            memo: memo,
            postings: [
                Posting(accountID: from, money: Money(-amount.amount, currency: amount.currency)),
                Posting(accountID: to, money: amount)
            ],
            state: .draft,
            origin: origin
        )
    }
}

private func requirePositive(_ amount: Money) throws {
    guard amount.amount > Decimal.zero else {
        throw TransactionCreationError.nonPositiveAmount(amount)
    }
}
