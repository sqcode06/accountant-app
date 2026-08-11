import Foundation

public struct BankLine: Hashable, Codable, Sendable {
    public var date: Date

    /// Signed from the account's point of view: negative when money left.
    public var amount: Decimal

    public var currency: Currency
    public var description: String
    public var externalID: String?

    /// A charge the bank listed separately from the amount.
    ///
    /// Some exports — Revolut among them — put fees in their own column, so the
    /// amount alone does not account for everything that left the account.
    /// Dropping it would leave the balance quietly short by the fee total.
    /// Always stored positive; it is a cost.
    public var fee: Decimal?

    public init(
        date: Date,
        amount: Decimal,
        currency: Currency,
        description: String,
        externalID: String? = nil,
        fee: Decimal? = nil
    ) {
        self.date = date
        self.amount = amount
        self.currency = currency
        self.description = description
        self.externalID = externalID
        self.fee = fee
    }

    /// True when the bank charged something on top of the amount.
    public var hasFee: Bool {
        guard let fee else { return false }
        return fee != .zero
    }
}
