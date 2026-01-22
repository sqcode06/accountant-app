import Foundation

public enum AccountNameResolution: Sendable {
    case keepLocal
    case preferIncoming
    case error
}

public enum TransactionConflictResolution: Sendable {
    case keepLocal
    case preferIncoming
    case error
}

public struct LedgerMergeOptions: Sendable {
    public var accountNameResolution: AccountNameResolution = .keepLocal
    public var transactionConflictResolution: TransactionConflictResolution = .error
    public var deduplicateByOrigin: Bool = true

    public init() {}
}

public enum LedgerMergeConflict: Sendable, Hashable {
    case accountNameMismatch(accountID: AccountID, local: String, incoming: String)
    case transactionIDMismatch(id: TransactionID)
    case transactionOriginMismatch(origin: TransactionOrigin)
}

public struct LedgerMergeReport: Sendable, Hashable {
    public var addedAccounts: Int = 0
    public var updatedAccounts: Int = 0
    public var addedTransactions: Int = 0
    public var skippedTransactions: Int = 0
    public var conflicts: [LedgerMergeConflict] = []

    public init() {}
}

public extension Ledger {

    // MARK: - Merge helpers

    /// Reindex in-memory maps after replacing an existing local transaction.
    /// IMPORTANT: this is only for the merge algorithm's transient indices.
    private static func _reindex(
        byID: inout [TransactionID: Transaction],
        byOrigin: inout [TransactionOrigin: Transaction],
        old: Transaction,
        new: Transaction
    ) {
        byID[old.id] = nil
        if let oo = old.origin, let cur = byOrigin[oo], cur.id == old.id {
            byOrigin[oo] = nil
        }

        byID[new.id] = new
        if let no = new.origin {
            byOrigin[no] = new
        }
    }

    /// Create a replacement transaction that keeps the provided `localID` but adopts
    /// the *financial content* of `incoming`.
    ///
    /// Policy for timestamps:
    /// - `createdAt`: keep local (identity stays local)
    /// - `updatedAt`: max(local.updatedAt, incoming.updatedAt)
    /// - `finalizedAt`: prefer incoming (finalized snapshot), fallback to local
    private static func _incomingAdoptingLocalID(
        _ incoming: Transaction,
        localID: TransactionID,
        local: Transaction
    ) -> Transaction {
        let updatedAt = max(local.updatedAt, incoming.updatedAt)
        let finalizedAt = incoming.finalizedAt ?? local.finalizedAt ?? nil

        return Transaction(
            id: localID,
            date: incoming.date,
            memo: incoming.memo,
            postings: incoming.postings,
            state: .finalized,
            createdAt: local.createdAt,
            updatedAt: updatedAt,
            finalizedAt: finalizedAt,
            origin: incoming.origin
        )
    }

    /// Merge *finalized* transactions from another ledger into this one.
    /// Intended for syncing/exported snapshots.
    mutating func mergeFinalized(from incoming: Ledger, options: LedgerMergeOptions = .init()) throws -> LedgerMergeReport {
        var report = LedgerMergeReport()

        // MARK: Merge accounts
        for acc in incoming.accounts.values {
            if let local = accounts[acc.id] {
                if local.name != acc.name {
                    switch options.accountNameResolution {
                    case .keepLocal:
                        report.conflicts.append(.accountNameMismatch(accountID: acc.id, local: local.name, incoming: acc.name))
                    case .preferIncoming:
                        _setAccount(acc)
                        report.updatedAccounts += 1
                    case .error:
                        throw LedgerMergeError.accountNameMismatch(accountID: acc.id, local: local.name, incoming: acc.name)
                    }
                }
            } else {
                _setAccount(acc)
                report.addedAccounts += 1
            }
        }

        // MARK: Build indices for existing transactions
        // IDs must be globally unique within the ledger (drafts included),
        // otherwise merge can create duplicate IDs.
        var byID: [TransactionID: Transaction] = [:]
        var byOrigin: [TransactionOrigin: Transaction] = [:]

        for tx in transactions {
            byID[tx.id] = tx
            if let o = tx.origin {
                byOrigin[o] = tx
            }
        }

        // MARK: Merge incoming finalized txs
        let incomingFinalized = incoming.transactions.filter { $0.state == .finalized }

        for inc in incomingFinalized {
            try inc.validate()

            // Ensure accounts exist (after account merge)
            for p in inc.postings {
                guard accounts[p.accountID] != nil else {
                    throw LedgerMergeError.incomingReferencesUnknownAccount(accountID: p.accountID, transactionID: inc.id)
                }
            }

            // A) Same ID already exists locally (draft or finalized)?
            if let local = byID[inc.id] {
                // Skip only if local already contains the exact same finalized fact.
                if local.state == .finalized,
                   local.financialSignature == inc.financialSignature,
                   local.origin == inc.origin {
                    report.skippedTransactions += 1
                    continue
                }

                report.conflicts.append(.transactionIDMismatch(id: inc.id))
                switch options.transactionConflictResolution {
                case .keepLocal:
                    report.skippedTransactions += 1
                    continue
                case .preferIncoming:
                    // Replace by ID (same ID), and keep indices consistent (including origin).
                    try _replaceTransaction(id: inc.id, with: inc)
                    Self._reindex(byID: &byID, byOrigin: &byOrigin, old: local, new: inc)
                    continue
                case .error:
                    throw LedgerMergeError.transactionIDConflict(id: inc.id, local: local, incoming: inc)
                }
            }

            // B) Dedupe by origin?
            if options.deduplicateByOrigin, let o = inc.origin, let local = byOrigin[o] {
                // If local already has the same finalized fact for this origin, skip.
                if local.state == .finalized, local.financialSignature == inc.financialSignature {
                    report.skippedTransactions += 1
                    continue
                }

                report.conflicts.append(.transactionOriginMismatch(origin: o))
                switch options.transactionConflictResolution {
                case .keepLocal:
                    report.skippedTransactions += 1
                    continue
                case .preferIncoming:
                    // Origin collision => “same real-world tx, different internal IDs”.
                    // Keep local identity stable and adopt incoming financial content.
                    let updated = Self._incomingAdoptingLocalID(inc, localID: local.id, local: local)

                    try _replaceTransaction(id: local.id, with: updated)

                    Self._reindex(byID: &byID, byOrigin: &byOrigin, old: local, new: updated)
                    continue
                case .error:
                    throw LedgerMergeError.transactionOriginConflict(origin: o, local: local, incoming: inc)
                }
            }

            // C) Brand new finalized transaction
            _appendTransaction(inc)
            byID[inc.id] = inc
            if let o = inc.origin { byOrigin[o] = inc }
            report.addedTransactions += 1
        }

        // Canonical ordering for deterministic persistence
        _reorderTransactionsCanonically()

        return report
    }
}
