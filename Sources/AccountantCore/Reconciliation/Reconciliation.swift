import Foundation

public enum ReconciliationStatus: String, Hashable, Codable, Sendable {
    case matched
    case mismatched
}

public enum ReconciliationError: Error, Equatable, Sendable {
    case unknownAccount(AccountID)
}

/// One transaction's effect on the account being reconciled, as a candidate for
/// ticking off against a statement.
///
/// This is what makes reconciliation actionable. A net difference tells you that
/// you disagree with the bank; a list of uncleared entries tells you where to look.
public struct UnclearedEntry: Hashable, Codable, Sendable {
    public let transactionID: TransactionID
    public let date: Date
    public let memo: String?
    public let delta: Money

    public init(transactionID: TransactionID, date: Date, memo: String?, delta: Money) {
        self.transactionID = transactionID
        self.date = date
        self.memo = memo
        self.delta = delta
    }
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

    /// Balance counting only postings the bank has confirmed.
    ///
    /// This is the number the ticking workflow drives: as entries are cleared,
    /// `clearedBalance` moves toward `statementBalance`. `ledgerBalance` above
    /// counts everything and answers the different question of whether the book
    /// as a whole agrees with the statement.
    public let clearedBalance: Money

    /// Entries not yet confirmed against a statement, oldest first. Together they
    /// account for the gap between `clearedBalance` and `ledgerBalance`.
    public let uncleared: [UnclearedEntry]

    public init(
        accountID: AccountID,
        currency: Currency,
        asOf: Date,
        ledgerBalance: Money,
        statementBalance: Money,
        difference: Money,
        status: ReconciliationStatus,
        includeDrafts: Bool,
        clearedBalance: Money,
        uncleared: [UnclearedEntry]
    ) {
        self.accountID = accountID
        self.currency = currency
        self.asOf = asOf
        self.ledgerBalance = ledgerBalance
        self.statementBalance = statementBalance
        self.difference = difference
        self.status = status
        self.includeDrafts = includeDrafts
        self.clearedBalance = clearedBalance
        self.uncleared = uncleared
    }

    /// Gap between the statement and what has actually been ticked off.
    /// Reaching zero is what "finished reconciling" means.
    public var clearedDifference: Money {
        Money(statementBalance.amount - clearedBalance.amount, currency: currency)
    }
}

public extension Ledger {
    /// Marks one account's postings within a transaction as cleared or uncleared.
    ///
    /// Deliberately permitted on finalized transactions. Clearing changes no
    /// accounting fact — it records that the bank confirmed one — so the
    /// draft-only restriction guarding `updateDraftTransaction` does not apply
    /// here. A finalized rent payment that has not yet appeared on the statement
    /// is exactly the case reconciliation exists to handle.
    ///
    /// Returns the number of postings actually changed, so a no-op stays cheap
    /// and detectable.
    @discardableResult
    mutating func setCleared(
        _ cleared: Bool,
        forAccount accountID: AccountID,
        in transactionID: TransactionID,
        now: Date = Date()
    ) throws -> Int {
        guard accounts[accountID] != nil else {
            throw ReconciliationError.unknownAccount(accountID)
        }

        guard let existing = transactions.first(where: { $0.id == transactionID }) else {
            throw LedgerError.transactionNotFound(transactionID)
        }

        var updated = existing
        var changed = 0

        for index in updated.postings.indices
        where updated.postings[index].accountID == accountID {
            guard updated.postings[index].cleared != cleared else { continue }
            updated.postings[index].cleared = cleared
            changed += 1
        }

        guard changed > 0 else { return 0 }

        updated.touch(now: now)
        try _replaceTransaction(id: transactionID, with: updated)

        return changed
    }

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

        let currency = statementBalance.currency
        var clearedTotal = Decimal.zero
        var uncleared: [UnclearedEntry] = []

        for tx in allTransactionsSorted(includeDrafts: includeDrafts) where tx.date <= date {
            let relevant = tx.postings.filter {
                $0.accountID == accountID && $0.money.currency == currency
            }
            guard !relevant.isEmpty else { continue }

            let clearedDelta = relevant
                .filter(\.cleared)
                .reduce(Decimal.zero) { $0 + $1.money.amount }
            clearedTotal += clearedDelta

            let unclearedDelta = relevant
                .filter { !$0.cleared }
                .reduce(Decimal.zero) { $0 + $1.money.amount }

            if unclearedDelta != Decimal.zero {
                uncleared.append(
                    UnclearedEntry(
                        transactionID: tx.id,
                        date: tx.date,
                        memo: tx.memo,
                        delta: Money(unclearedDelta, currency: currency)
                    )
                )
            }
        }

        return ReconciliationReport(
            accountID: accountID,
            currency: currency,
            asOf: date,
            ledgerBalance: ledgerBalance,
            statementBalance: statementBalance,
            difference: difference,
            status: status,
            includeDrafts: includeDrafts,
            clearedBalance: Money(clearedTotal, currency: currency),
            uncleared: uncleared
        )
    }
}
