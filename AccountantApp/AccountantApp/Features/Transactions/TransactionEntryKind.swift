import AccountantCore

enum TransactionEntryKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    var id: Self { self }

    var title: String {
        switch self {
        case .expense:
            "Expense"
        case .income:
            "Income"
        case .transfer:
            "Transfer"
        }
    }

    var systemImageName: String {
        switch self {
        case .expense:
            "cart.fill"
        case .income:
            "arrow.down.circle.fill"
        case .transfer:
            "arrow.left.arrow.right.circle.fill"
        }
    }

    var primaryAccountTitle: String {
        switch self {
        case .expense:
            "Paid from"
        case .income:
            "Received in"
        case .transfer:
            "From"
        }
    }

    var counterpartAccountTitle: String {
        switch self {
        case .expense:
            "Category"
        case .income:
            "Source"
        case .transfer:
            "To"
        }
    }

    var primaryAccountKinds: [AccountKind] {
        switch self {
        case .expense, .income, .transfer:
            [.asset, .liability, .clearing]
        }
    }

    var counterpartAccountKinds: [AccountKind] {
        switch self {
        case .expense:
            [.expense]
        case .income:
            [.income]
        case .transfer:
            [.asset, .liability, .clearing]
        }
    }

    var memoPlaceholder: String {
        switch self {
        case .expense:
            "Groceries, rent, coffee..."
        case .income:
            "Salary, refund, freelance..."
        case .transfer:
            "Move to savings..."
        }
    }

    var emptyRequirementMessage: String {
        switch self {
        case .expense:
            "Create at least one payment account and one expense account before recording an expense."
        case .income:
            "Create at least one receiving account and one income account before recording income."
        case .transfer:
            "Create at least two balance accounts before recording a transfer."
        }
    }

    /// One line explaining what this type records, shown under the type switcher.
    var summary: String {
        switch self {
        case .expense:
            "Money leaving an account for a category."
        case .income:
            "Money arriving into an account from a source."
        case .transfer:
            "Money moving between two of your own accounts."
        }
    }
}
