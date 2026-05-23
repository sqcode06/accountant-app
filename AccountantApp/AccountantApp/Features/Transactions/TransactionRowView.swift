import SwiftUI
import AccountantCore

struct TransactionRowView: View {
    let transaction: AccountantCore.Transaction
    let accounts: [AccountID: Account]
    let onFinalize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: displayKind.systemImageName)
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(displayKind.tint.opacity(0.14), in: Circle())
                    .foregroundStyle(displayKind.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(amountText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(displayKind.tint)

                    stateChip
                }
            }

            if transaction.state == .draft {
                Button {
                    onFinalize()
                } label: {
                    Label("Finalize", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var title: String {
        let cleanedMemo = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanedMemo.isEmpty ? displayKind.title : cleanedMemo
    }

    private var subtitle: String {
        let accountNames = transaction.postings
            .compactMap { accounts[$0.accountID]?.name }
            .joined(separator: " → ")

        if accountNames.isEmpty {
            return DateDisplay.transactionDate(transaction.date)
        }

        return "\(DateDisplay.transactionDate(transaction.date)) · \(accountNames)"
    }

    private var amountText: String {
        guard let money = displayMoney else { return "—" }
        return displayKind.amountPrefix + MoneyDisplay.string(money)
    }

    private var stateChip: some View {
        Text(transaction.state == .draft ? "Draft" : "Finalized")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stateTint.opacity(0.16), in: Capsule())
            .foregroundStyle(stateTint)
    }

    private var stateTint: Color {
        transaction.state == .draft ? .orange : .green
    }

    private var displayKind: TransactionDisplayKind {
        let kinds = Set(transaction.postings.compactMap { accounts[$0.accountID]?.kind })
        let balanceKinds = Set<AccountKind>([.asset, .liability, .clearing])

        if kinds.contains(.expense) {
            return .expense
        }

        if kinds.contains(.income) {
            return .income
        }

        if !kinds.isEmpty, kinds.isSubset(of: balanceKinds) {
            return .transfer
        }

        return .adjustment
    }

    private var displayMoney: Money? {
        switch displayKind {
        case .expense:
            return positiveMoney(for: .expense)
        case .income:
            return positiveMoney(for: .income)
        case .transfer:
            return transaction.postings
                .first { $0.money.amount > .zero }
                .map { Money(abs($0.money.amount), currency: $0.money.currency) }
        case .adjustment:
            return transaction.postings.first.map {
                Money(abs($0.money.amount), currency: $0.money.currency)
            }
        }
    }

    private func positiveMoney(for kind: AccountKind) -> Money? {
        transaction.postings
            .first { accounts[$0.accountID]?.kind == kind }
            .map { Money(abs($0.money.amount), currency: $0.money.currency) }
    }

    private func abs(_ amount: Decimal) -> Decimal {
        amount < .zero ? -amount : amount
    }
}

private enum TransactionDisplayKind {
    case expense
    case income
    case transfer
    case adjustment

    var title: String {
        switch self {
        case .expense:
            "Expense"
        case .income:
            "Income"
        case .transfer:
            "Transfer"
        case .adjustment:
            "Transaction"
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
        case .adjustment:
            "doc.text.fill"
        }
    }

    var tint: Color {
        switch self {
        case .expense:
            .red
        case .income:
            .green
        case .transfer:
            .blue
        case .adjustment:
            .secondary
        }
    }

    var amountPrefix: String {
        switch self {
        case .expense:
            "-"
        case .income:
            "+"
        case .transfer, .adjustment:
            ""
        }
    }
}
