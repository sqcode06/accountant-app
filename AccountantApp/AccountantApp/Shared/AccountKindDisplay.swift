import AccountantCore

enum AccountKindCatalog {
    /// The four kinds that describe money as people actually think about it.
    static let everyday: [AccountKind] = [
        .asset,
        .liability,
        .income,
        .expense
    ]

    /// Accounting machinery. Real, occasionally necessary, and meaningless to
    /// anyone who has not done double-entry bookkeeping before — so it stays
    /// behind a disclosure rather than sitting in the middle of the list you pick
    /// from when adding your current account.
    static let advanced: [AccountKind] = [
        .equity,
        .clearing
    ]

    /// Every kind, in display order. The order is load-bearing: `sortIndex`
    /// derives account sorting from it.
    static let all: [AccountKind] = everyday + advanced

    static func sortIndex(for kind: AccountKind) -> Int {
        all.firstIndex(of: kind) ?? Int.max
    }

    static func isAdvanced(_ kind: AccountKind) -> Bool {
        advanced.contains(kind)
    }
}

extension AccountKind {
    /// What this kind means, in the words someone would use themselves.
    var plainDescription: String {
        switch self {
        case .asset:
            "Money you have — a bank account, cash, savings."
        case .liability:
            "Money you owe — a credit card, a loan."
        case .income:
            "Where money comes from — salary, refunds."
        case .expense:
            "What you spend on — groceries, rent, transport."
        case .equity:
            "Opening balances and adjustments that are not real transactions."
        case .clearing:
            "A holding place for money in transit between two accounts."
        }
    }

    var displayName: String {
        switch self {
        case .asset:
            "Asset"
        case .liability:
            "Liability"
        case .income:
            "Income"
        case .expense:
            "Expense"
        case .equity:
            "Equity"
        case .clearing:
            "Clearing"
        }
    }

    var systemImageName: String {
        switch self {
        case .asset:
            "banknote"
        case .liability:
            "creditcard"
        case .income:
            "arrow.down.circle"
        case .expense:
            "cart"
        case .equity:
            "scale.3d"
        case .clearing:
            "tray.and.arrow.down"
        }
    }
}

extension AccountStatus {
    var displayName: String {
        switch self {
        case .active:
            "Active"
        case .archived:
            "Archived"
        }
    }
}

extension Sequence where Element == Account {
    func sortedForDisplay() -> [Account] {
        sorted {
            let lhsKindIndex = AccountKindCatalog.sortIndex(for: $0.kind)
            let rhsKindIndex = AccountKindCatalog.sortIndex(for: $1.kind)

            if lhsKindIndex != rhsKindIndex {
                return lhsKindIndex < rhsKindIndex
            }

            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }
}
