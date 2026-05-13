import Foundation

public enum ReconciliationStatus: String, Hashable, Codable, Sendable {
    case matched
    case mismatched
}

public enum ReconciliationError: Error, Equatable, Sendable {
    case unknownAccount(AccountID)
}

public struct ReconciliationReport: Hashable, Codable, Sendable {
    public let accountID: AccountID
    public let currency: Currency
    public let asOf: Date
    public let ledgerBalance: Money
    public let statementBalance: Money
    public let difference: Money
    public let status: ReconciliationStatus
    public let includeDrafts: Bool

    public init(
        accountID: AccountID,
        currency: Currency,
        asOf: Date,
        ledgerBalance: Money,
        statementBalance: Money,
        difference: Money,
        status: ReconciliationStatus,
        includeDrafts: Bool
    ) {
        self.accountID = accountID
        self.currency = currency
        self.asOf = asOf
        self.ledgerBalance = ledgerBalance
        self.statementBalance = statementBalance
        self.difference = difference
        self.status = status
        self.includeDrafts = includeDrafts
    }
}

public extension Ledger {
    /// Compares the ledger balance of one account against a statement balance.
    ///
    /// Reconciliation is read-only. Archived accounts remain reconcilable because
    /// historical balances are still meaningful after an account is closed.
    /// Drafts are excluded by default because reconciliation should normally
    /// compare trusted ledger facts against an external statement.
    func reconcileAccount(
        _ accountID: AccountID,
        statementBalance: Money,
        asOf date: Date,
        includeDrafts: Bool = false
    ) throws -> ReconciliationReport {
        guard accounts[accountID] != nil else {
            throw ReconciliationError.unknownAccount(accountID)
        }

        let ledgerBalance = balance(
            of: accountID,
            currency: statementBalance.currency,
            asOf: date,
            includeDrafts: includeDrafts
        )

        let differenceAmount = statementBalance.amount - ledgerBalance.amount
        let difference = Money(differenceAmount, currency: statementBalance.currency)
        let status: ReconciliationStatus = differenceAmount == Decimal.zero ? .matched : .mismatched

        return ReconciliationReport(
            accountID: accountID,
            currency: statementBalance.currency,
            asOf: date,
            ledgerBalance: ledgerBalance,
            statementBalance: statementBalance,
            difference: difference,
            status: status,
            includeDrafts: includeDrafts
        )
    }
}
