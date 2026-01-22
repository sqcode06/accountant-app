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
    public var rules: [ImportRule] = []

    public init(source: String, statementAccountID: AccountID, defaultCounterpartyAccountID: AccountID) {
        self.source = source
        self.statementAccountID = statementAccountID
        self.defaultCounterpartyAccountID = defaultCounterpartyAccountID
    }

    public mutating func addRule(_ rule: ImportRule) {
        rules.append(rule)
    }

    public func makeDraft(from line: BankLine, now: Date = Date()) throws -> Transaction {
        var tx = Transaction.draft(
            date: line.date,
            memo: line.description,
            postings: [
                Posting(accountID: statementAccountID, money: Money(line.amount, currency: line.currency)),
                Posting(accountID: defaultCounterpartyAccountID, money: Money(-line.amount, currency: line.currency))
            ]
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
}
