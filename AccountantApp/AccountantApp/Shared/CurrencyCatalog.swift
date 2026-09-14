import Foundation
import AccountantCore

/// Currencies offered in pickers.
///
/// Deliberately a short list rather than all ~180 ISO codes: this is a personal
/// budgeting app, and a wall of currencies is worse than a handful plus the
/// ability to add more later.
enum CurrencyCatalog {
    static let common: [Currency] = [
        Currency("EUR"),
        Currency("USD"),
        Currency("GBP"),
        Currency("SEK"),
        Currency("NOK"),
        Currency("DKK"),
        Currency("PLN"),
        Currency("CHF")
    ]

    /// Returns the common list, guaranteeing `preferred` appears in it.
    static func options(including preferred: Currency) -> [Currency] {
        common.contains(preferred) ? common : [preferred] + common
    }

    static func displayName(for currency: Currency) -> String {
        let localized = Locale.current.localizedString(forCurrencyCode: currency.code)

        guard let localized, !localized.isEmpty else {
            return currency.code
        }

        return "\(currency.code) · \(localized)"
    }
}

extension AccountKind {
    /// Whether accounts of this kind hold a balance in one specific currency.
    ///
    /// Assets and liabilities do — a bank account holds euros and nothing else.
    /// Categories do not: groceries bought in euros and in dollars are both
    /// groceries, so forcing a single currency on them would be wrong.
    var isDenominated: Bool {
        switch self {
        case .asset, .liability, .clearing:
            true
        case .income, .expense, .equity:
            false
        }
    }
}
