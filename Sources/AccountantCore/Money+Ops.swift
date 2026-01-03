import Foundation

public extension Money {
    static func zero(currency: Currency) -> Money {
        Money(Decimal.zero, currency: currency)
    }

    func adding(_ other: Money) throws -> Money {
        guard currency == other.currency else { throw LedgerError.mixedCurrencies }
        return Money(amount + other.amount, currency: currency)
    }
}
