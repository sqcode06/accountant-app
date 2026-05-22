import AccountantCore

enum AccountKindCatalog {
    static let all: [AccountKind] = [
        .asset,
        .liability,
        .income,
        .expense,
        .equity,
        .clearing
    ]
}

extension AccountKind {
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
