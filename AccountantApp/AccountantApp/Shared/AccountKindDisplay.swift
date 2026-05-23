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
    
    static func sortIndex(for kind: AccountKind) -> Int {
        all.firstIndex(of: kind) ?? Int.max
    }
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
