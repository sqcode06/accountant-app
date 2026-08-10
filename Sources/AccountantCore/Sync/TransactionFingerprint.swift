import Foundation

/// Identifies a transaction by the money it moves, and nothing else.
///
/// Merge uses this to answer "does the local ledger already hold this same
/// finalized fact?" Anything included here that is *not* part of the financial
/// fact will show up as a spurious conflict during sync.
///
/// `Posting.cleared` is deliberately excluded for exactly that reason. Clearing
/// records whether this device's statement has confirmed the movement — local
/// bookkeeping state, not a property of the movement. Two devices can legitimately
/// disagree about it while describing the same transaction, and comparing whole
/// `Posting` values would turn that disagreement into a conflict that could
/// overwrite a completed reconciliation.
internal struct TransactionFingerprint: Hashable {

    /// One posting's financial content.
    internal struct Entry: Hashable {
        let accountID: AccountID
        let currency: Currency
        let amount: Decimal
    }

    let date: Date
    let entries: [Entry]

    init(tx: Transaction) {
        self.date = tx.date

        self.entries = tx.postings
            .map {
                Entry(
                    accountID: $0.accountID,
                    currency: $0.money.currency,
                    amount: $0.money.amount
                )
            }
            .sorted {
                if $0.accountID != $1.accountID {
                    return $0.accountID.rawValue.uuidString < $1.accountID.rawValue.uuidString
                }
                if $0.currency != $1.currency {
                    return $0.currency.code < $1.currency.code
                }

                return $0.amount < $1.amount
            }
    }
}

internal extension Transaction {
    var financialSignature: TransactionFingerprint { TransactionFingerprint(tx: self) }
}
