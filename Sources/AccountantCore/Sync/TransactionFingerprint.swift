import Foundation

internal struct TransactionFingerprint: Hashable {
    let date: Date
    let postings: [Posting]

    init(tx: Transaction) {
        self.date = tx.date

        self.postings = tx.postings.sorted {
            if $0.accountID != $1.accountID {
                return $0.accountID.rawValue.uuidString < $1.accountID.rawValue.uuidString
            }
            if $0.money.currency != $1.money.currency {
                return $0.money.currency.code < $1.money.currency.code
            }

            return $0.money.amount < $1.money.amount
        }
    }
}

internal extension Transaction {
    var financialSignature: TransactionFingerprint { TransactionFingerprint(tx: self) }
}
