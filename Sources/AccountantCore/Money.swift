import Foundation

public struct Money: Hashable, Codable, Sendable {
    public let currency: Currency
    public let amount: Decimal

    public init(_ amount: Decimal, currency: Currency) {
        self.amount = amount
        self.currency = currency
    }
}
