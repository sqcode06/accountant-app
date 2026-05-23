import Foundation
import AccountantCore

enum MoneyDisplay {
    static func string(_ money: Money) -> String {
        string(amount: money.amount, currency: money.currency)
    }

    static func string(amount: Decimal, currency: Currency) -> String {
        amount.formatted(.currency(code: currency.code))
    }
}
