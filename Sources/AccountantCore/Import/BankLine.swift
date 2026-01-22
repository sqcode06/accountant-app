import Foundation

public struct BankLine: Hashable, Codable, Sendable {
    public var date: Date
    public var amount: Decimal
    public var currency: Currency
    public var description: String
    public var externalID: String?

    public init(date: Date, amount: Decimal, currency: Currency, description: String, externalID: String? = nil) {
        self.date = date
        self.amount = amount
        self.currency = currency
        self.description = description
        self.externalID = externalID
    }
}
