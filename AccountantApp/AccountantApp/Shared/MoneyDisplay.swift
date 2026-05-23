import Foundation
import AccountantCore

enum MoneyDisplay {
    static func string(_ money: Money) -> String {
        string(amount: money.amount, currency: money.currency)
    }

    static func string(amount: Decimal, currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? "\(NSDecimalNumber(decimal: amount)) \(currency.code)"
    }
}
