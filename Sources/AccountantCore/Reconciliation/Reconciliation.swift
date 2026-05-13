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
    func reconcileAccount(
        _ accountID: AccountID,
        statementBalance: Money,
        asOf date: Date,
        includeDrafts: Bool = false
    ) throws -> ReconciliationReport {
        ReconciliationReport(
            accountID: accountID,
            currency: statementBalance.currency,
            asOf: date,
            ledgerBalance: .zero(currency: statementBalance.currency),
            statementBalance: statementBalance,
            difference: statementBalance,
            status: statementBalance.amount == Decimal.zero ? .matched : .mismatched,
            includeDrafts: includeDrafts
        )
    }
}
