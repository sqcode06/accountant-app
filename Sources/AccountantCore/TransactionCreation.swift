import Foundation

public enum TransactionCreationError: Error, Equatable, Sendable {
    case nonPositiveAmount(Money)
}

public extension Transaction {
    static func draftExpense(
        paidFrom: AccountID,
        category: AccountID,
        amount: Money,
        date: Date = Date(),
        memo: String? = nil,
        origin: TransactionOrigin? = nil
    ) throws -> Transaction {
        Transaction(
            date: date,
            memo: memo,
            postings: [],
            state: .draft,
            origin: origin
        )
    }

    static func draftIncome(
        receivedIn: AccountID,
        source: AccountID,
        amount: Money,
        date: Date = Date(),
        memo: String? = nil,
        origin: TransactionOrigin? = nil
    ) throws -> Transaction {
        Transaction(
            date: date,
            memo: memo,
            postings: [],
            state: .draft,
            origin: origin
        )
    }

    static func draftTransfer(
        from: AccountID,
        to: AccountID,
        amount: Money,
        date: Date = Date(),
        memo: String? = nil,
        origin: TransactionOrigin? = nil
    ) throws -> Transaction {
        Transaction(
            date: date,
            memo: memo,
            postings: [],
            state: .draft,
            origin: origin
        )
    }
}
