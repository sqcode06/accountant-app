import Foundation

public struct ImportRule {
    public let name: String
    public let applies: (BankLine) -> Bool
    public let transform: (BankLine, inout Transaction) -> Void

    public init(name: String, applies: @escaping (BankLine) -> Bool, transform: @escaping (BankLine, inout Transaction) -> Void) {
        self.name = name
        self.applies = applies
        self.transform = transform
    }
}

public struct ImportPipeline {
    public var source: String
    public var statementAccountID: AccountID
    public var defaultCounterpartyAccountID: AccountID

    /// Where separately listed bank charges go.
    ///
    /// Required only for statements that actually carry a fee column. A line with
    /// a fee and nowhere to put it fails visibly rather than quietly losing the
    /// money or burying it in the merchant's category.
    public var feeAccountID: AccountID?

    public var rules: [ImportRule] = []

    public init(
        source: String,
        statementAccountID: AccountID,
        defaultCounterpartyAccountID: AccountID,
        feeAccountID: AccountID? = nil
    ) {
        self.source = source
        self.statementAccountID = statementAccountID
        self.defaultCounterpartyAccountID = defaultCounterpartyAccountID
        self.feeAccountID = feeAccountID
    }

    public mutating func addRule(_ rule: ImportRule) {
        rules.append(rule)
    }

    public func makeDraft(from line: BankLine, now: Date = Date()) throws -> Transaction {
        var tx = Transaction.draft(
            date: line.date,
            memo: line.description,
            postings: try postings(for: line)
        )

        if let ext = line.externalID {
            tx.origin = TransactionOrigin(source: source, externalID: ext)
        }

        for rule in rules where rule.applies(line) {
            rule.transform(line, &tx)
        }

        tx.touch(now: now)
        try tx.validate()
        return tx
    }

    public func makeDrafts(from lines: [BankLine], now: Date = Date()) throws -> [Transaction] {
        try lines.map { try makeDraft(from: $0, now: now) }
    }

    /// Builds the postings for one statement line.
    ///
    /// A fee becomes a third posting on the *same* transaction rather than a
    /// second transaction, because the bank shows one line and reconciliation
    /// ticks statement lines off against transactions. Two transactions for one
    /// line would leave one of them permanently unmatched.
    ///
    /// The account's balance moves by `amount - fee`: the fee is a cost charged on
    /// top, so an outflow of 3.00 with a 0.50 fee takes 3.50 out, and an inflow of
    /// 45.00 with a 0.50 fee brings 44.50 in. The three postings still sum to zero.
    private func postings(for line: BankLine) throws -> [Posting] {
        let currency = line.currency

        guard let fee = line.fee, fee != .zero else {
            return [
                Posting(accountID: statementAccountID, money: Money(line.amount, currency: currency)),
                Posting(accountID: defaultCounterpartyAccountID, money: Money(-line.amount, currency: currency))
            ]
        }

        guard let feeAccountID else {
            throw ImportError.feeAccountMissing
        }

        return [
            Posting(accountID: statementAccountID, money: Money(line.amount - fee, currency: currency)),
            Posting(accountID: defaultCounterpartyAccountID, money: Money(-line.amount, currency: currency)),
            Posting(accountID: feeAccountID, money: Money(fee, currency: currency))
        ]
    }
}
