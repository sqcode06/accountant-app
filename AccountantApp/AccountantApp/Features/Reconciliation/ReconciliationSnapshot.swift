import Foundation
import AccountantCore

struct ReconciliationSnapshot: Hashable {
    let account: Account
    let report: ReconciliationReport

    static func make(
        from ledger: Ledger,
        accountID: AccountID,
        statementBalance: Decimal,
        currency: Currency,
        asOf date: Date
    ) throws -> ReconciliationSnapshot {
        guard let account = ledger.accounts[accountID] else {
            throw ReconciliationError.unknownAccount(accountID)
        }

        let report = try ledger.reconcileAccount(
            accountID,
            statementBalance: Money(statementBalance, currency: currency),
            asOf: date,
            includeDrafts: false
        )

        return ReconciliationSnapshot(account: account, report: report)
    }

    var statusTitle: String {
        isMatched ? "Matched" : "Mismatched"
    }

    var statusMessage: String {
        if isMatched {
            return "Ledger and statement balances agree."
        }

        return "Statement and ledger differ by \(MoneyDisplay.string(report.difference))."
    }

    var isMatched: Bool {
        report.status == .matched
    }
}
