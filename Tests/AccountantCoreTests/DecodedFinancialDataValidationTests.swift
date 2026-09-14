import Foundation
import XCTest
@testable import AccountantCore

final class DecodedFinancialDataValidationTests: XCTestCase {
    private let accountA = "11111111-1111-1111-1111-111111111111"
    private let accountB = "22222222-2222-2222-2222-222222222222"
    private let transactionA = "33333333-3333-3333-3333-333333333333"
    private let nilID = "00000000-0000-0000-0000-000000000000"

    func testDuplicateAccountIDsProduceARecoverableDecodeError() {
        let account = accountJSON(id: accountA, name: "Cash")
        let json = ledgerJSON(accounts: [account, account], transactions: [])

        XCTAssertThrowsError(try decodeLedger(json)) { error in
            XCTAssertEqual(
                error as? LedgerValidationError,
                .duplicateAccountID(AccountID(UUID(uuidString: self.accountA)!))
            )
        }
    }

    func testNilAccountAndTransactionIdentitiesAreRejected() {
        XCTAssertThrowsError(
            try decodeLedger(ledgerJSON(
                accounts: [accountJSON(id: nilID, name: "Cash")],
                transactions: []
            ))
        ) { error in
            XCTAssertEqual(
                error as? LedgerValidationError,
                .invalidAccountID(AccountID(UUID(uuidString: self.nilID)!))
            )
        }

        let transaction = transactionJSON(
            id: nilID,
            postings: [postingJSON(accountID: accountA, amount: -1),
                       postingJSON(accountID: accountB, amount: 1)]
        )
        XCTAssertThrowsError(
            try decodeLedger(ledgerJSON(
                accounts: [accountJSON(id: accountA, name: "Cash"),
                           accountJSON(id: accountB, name: "Other")],
                transactions: [transaction]
            ))
        ) { error in
            XCTAssertEqual(
                error as? LedgerValidationError,
                .invalidTransactionID(TransactionID(UUID(uuidString: self.nilID)!))
            )
        }
    }

    func testDuplicateTransactionIDsAreRejected() {
        let transaction = transactionJSON(
            id: transactionA,
            postings: [postingJSON(accountID: accountA, amount: -1),
                       postingJSON(accountID: accountB, amount: 1)]
        )
        let json = ledgerJSON(
            accounts: [accountJSON(id: accountA, name: "Cash"),
                       accountJSON(id: accountB, name: "Other")],
            transactions: [transaction, transaction]
        )

        XCTAssertThrowsError(try decodeLedger(json)) { error in
            XCTAssertEqual(
                error as? LedgerError,
                .duplicateTransactionID(TransactionID(UUID(uuidString: self.transactionA)!))
            )
        }
    }

    func testDanglingPostingReferenceIsRejected() {
        let transaction = transactionJSON(
            id: transactionA,
            postings: [postingJSON(accountID: accountA, amount: -1),
                       postingJSON(accountID: accountB, amount: 1)]
        )

        XCTAssertThrowsError(try decodeLedger(ledgerJSON(
            accounts: [accountJSON(id: accountA, name: "Cash")],
            transactions: [transaction]
        ))) { error in
            XCTAssertEqual(
                error as? LedgerError,
                .unknownAccount(AccountID(UUID(uuidString: self.accountB)!))
            )
        }
    }

    func testMalformedDoubleEntryTransactionsAreRejected() {
        let accounts = [accountJSON(id: accountA, name: "Cash"),
                        accountJSON(id: accountB, name: "Other")]

        XCTAssertThrowsError(try decodeLedger(ledgerJSON(
            accounts: accounts,
            transactions: [transactionJSON(
                id: transactionA,
                postings: [postingJSON(accountID: accountA, amount: 1)]
            )]
        ))) { error in
            XCTAssertEqual(error as? LedgerError, .emptyTransaction)
        }

        XCTAssertThrowsError(try decodeLedger(ledgerJSON(
            accounts: accounts,
            transactions: [transactionJSON(
                id: transactionA,
                postings: [postingJSON(accountID: accountA, amount: -1),
                           postingJSON(accountID: accountB, amount: 2)]
            )]
        ))) { error in
            XCTAssertEqual(error as? LedgerError, .unbalancedTransaction(sum: 1))
        }

        XCTAssertThrowsError(try decodeLedger(ledgerJSON(
            accounts: accounts,
            transactions: [transactionJSON(
                id: transactionA,
                postings: [postingJSON(accountID: accountA, amount: -1, currency: "EUR"),
                           postingJSON(accountID: accountB, amount: 1, currency: "USD")]
            )]
        ))) { error in
            XCTAssertEqual(error as? LedgerError, .mixedCurrencies)
        }
    }

    func testPostingCurrencyMustMatchItsAccountCurrency() {
        let transaction = transactionJSON(
            id: transactionA,
            postings: [postingJSON(accountID: accountA, amount: -1, currency: "USD"),
                       postingJSON(accountID: accountB, amount: 1, currency: "USD")]
        )
        let json = ledgerJSON(
            accounts: [accountJSON(id: accountA, name: "Bank", currency: "EUR"),
                       accountJSON(id: accountB, name: "Other")],
            transactions: [transaction]
        )

        XCTAssertThrowsError(try decodeLedger(json)) { error in
            XCTAssertEqual(
                error as? LedgerError,
                .accountCurrencyMismatch(
                    AccountID(UUID(uuidString: self.accountA)!),
                    expected: Currency("EUR"),
                    actual: Currency("USD")
                )
            )
        }
    }

    func testInvalidCurrencyAndNonNumericMoneyAreRejectedByValidation() {
        let cash = Account(name: "Cash")
        let other = Account(name: "Other")
        var ledger = Ledger()
        ledger.addAccount(cash)
        ledger.addAccount(other)

        ledger._appendTransaction(Transaction(postings: [
            Posting(accountID: cash.id, money: Money(-1, currency: Currency("EURO"))),
            Posting(accountID: other.id, money: Money(1, currency: Currency("EURO")))
        ]))
        XCTAssertThrowsError(try ledger.validate()) { error in
            XCTAssertEqual(error as? LedgerError, .invalidCurrencyCode("EURO"))
        }

        var notANumberLedger = Ledger()
        notANumberLedger.addAccount(cash)
        notANumberLedger.addAccount(other)
        let notANumber = NSDecimalNumber.notANumber.decimalValue
        notANumberLedger._appendTransaction(Transaction(postings: [
            Posting(accountID: cash.id, money: Money(notANumber, currency: Currency("EUR"))),
            Posting(accountID: other.id, money: Money(notANumber, currency: Currency("EUR")))
        ]))
        XCTAssertThrowsError(try notANumberLedger.validate()) { error in
            XCTAssertEqual(error as? LedgerError, .invalidMonetaryAmount)
        }
    }

    func testArchivedAccountHistoryStillDecodesAndRoundTrips() throws {
        let transaction = transactionJSON(
            id: transactionA,
            postings: [postingJSON(accountID: accountA, amount: -10),
                       postingJSON(accountID: accountB, amount: 10)]
        )
        let ledger = try decodeLedger(ledgerJSON(
            accounts: [accountJSON(id: accountA, name: "Old bank", status: "archived", currency: "EUR"),
                       accountJSON(id: accountB, name: "Groceries", kind: "expense", status: "archived")],
            transactions: [transaction]
        ))

        XCTAssertNoThrow(try ledger.validate())
        XCTAssertEqual(ledger.transactions.count, 1)

        let encoder = JSONEncoder()
        LedgerDateCoding.apply(to: encoder)
        let decoder = JSONDecoder()
        LedgerDateCoding.apply(to: decoder)
        XCTAssertEqual(try decoder.decode(Ledger.self, from: encoder.encode(ledger)), ledger)
    }

    func testPersistedLedgerAcceptsHistoricalAndCurrentSchemas() throws {
        for version in [3, PersistedLedger.currentSchemaVersion] {
            let json = """
            {
              "schemaVersion": \(version),
              "savedAt": "0",
              "ledger": {
                "accounts": [
                  {"id":{"rawValue":"\(accountA)"},"name":"Historical","kind":"expense","status":"archived"}
                ],
                "transactions": []
              }
            }
            """
            let restored = try decodePersistedLedger(json)
            XCTAssertEqual(restored.schemaVersion, version)
            let account = try XCTUnwrap(restored.ledger.accounts.values.first)
            XCTAssertNil(account.currency)
            XCTAssertEqual(account.sortOrder, 0)
        }
    }

    func testPersistedLedgerRejectsVersionsOutsideItsSupportedRange() {
        for version in [0, PersistedLedger.currentSchemaVersion + 1] {
            let json = """
            {"schemaVersion":\(version),"savedAt":"0","ledger":{"accounts":[],"transactions":[]}}
            """
            XCTAssertThrowsError(try decodePersistedLedger(json)) { error in
                XCTAssertEqual(error as? LedgerStoreError, .unsupportedSchemaVersion(version))
            }
        }
    }

    // MARK: - JSON fixtures

    private func decodeLedger(_ json: String) throws -> Ledger {
        let decoder = JSONDecoder()
        LedgerDateCoding.apply(to: decoder)
        return try decoder.decode(Ledger.self, from: Data(json.utf8))
    }

    private func decodePersistedLedger(_ json: String) throws -> PersistedLedger {
        let decoder = JSONDecoder()
        LedgerDateCoding.apply(to: decoder)
        return try decoder.decode(PersistedLedger.self, from: Data(json.utf8))
    }

    private func accountJSON(
        id: String,
        name: String,
        kind: String = "asset",
        status: String = "active",
        currency: String? = nil
    ) -> String {
        let currencyField = currency.map { ",\"currency\":{\"code\":\"\($0)\"}" } ?? ""
        return """
        {"id":{"rawValue":"\(id)"},"name":"\(name)","kind":"\(kind)","status":"\(status)"\(currencyField)}
        """
    }

    private func postingJSON(accountID: String, amount: Int, currency: String = "EUR") -> String {
        """
        {"accountID":{"rawValue":"\(accountID)"},"money":{"amount":\(amount),"currency":{"code":"\(currency)"}}}
        """
    }

    private func transactionJSON(id: String, postings: [String]) -> String {
        """
        {"id":{"rawValue":"\(id)"},"date":"0","postings":[\(postings.joined(separator: ","))]}
        """
    }

    private func ledgerJSON(accounts: [String], transactions: [String]) -> String {
        """
        {"accounts":[\(accounts.joined(separator: ","))],"transactions":[\(transactions.joined(separator: ","))]}
        """
    }
}

final class LedgerBackupDataValidationTests: XCTestCase {
    private let eur = Currency("EUR")

    func testDecodedBackupMapsInvalidLedgerToUnreadable() throws {
        let json = """
        {
          "formatVersion": 1,
          "createdAt": "0",
          "ledger": {
            "accounts": [
              {"id":{"rawValue":"11111111-1111-1111-1111-111111111111"},"name":"Only","kind":"asset","status":"active"}
            ],
            "transactions": [
              {"id":{"rawValue":"33333333-3333-3333-3333-333333333333"},"date":"0","postings":[
                {"accountID":{"rawValue":"11111111-1111-1111-1111-111111111111"},"money":{"amount":1,"currency":{"code":"EUR"}}}
              ]}
            ]
          }
        }
        """

        XCTAssertThrowsError(try LedgerBackupCoder.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? LedgerBackupError, .unreadable)
        }
    }

    func testProgrammaticBackupRejectsDanglingBudgetReference() throws {
        let missing = AccountID()
        let target = BudgetTarget(
            accountID: missing,
            amount: Money(100, currency: eur),
            effectiveFrom: BudgetPeriod(year: 2026, month: 9)
        )
        let backup = LedgerBackup(ledger: Ledger(), budget: Budget(targets: [target]))

        XCTAssertThrowsError(try backup.validateForRestore()) { error in
            XCTAssertEqual(
                error as? LedgerBackupValidationError,
                .unknownBudgetAccount(missing)
            )
        }
    }

    func testProgrammaticBackupRejectsDuplicateBudgetAndRuleIdentities() throws {
        var ledger = Ledger()
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(groceries)

        let targetID = BudgetTargetID()
        let target = BudgetTarget(
            id: targetID,
            accountID: groceries.id,
            amount: Money(100, currency: eur),
            effectiveFrom: BudgetPeriod(year: 2026, month: 9)
        )
        XCTAssertThrowsError(try LedgerBackup(
            ledger: ledger,
            budget: Budget(targets: [target, target])
        ).validateForRestore()) { error in
            XCTAssertEqual(
                error as? LedgerBackupValidationError,
                .duplicateBudgetTargetID(targetID)
            )
        }

        let ruleID = UUID()
        let first = ClassificationRuleConfiguration(id: ruleID, needle: "first")
        let second = ClassificationRuleConfiguration(id: ruleID, needle: "second")
        XCTAssertThrowsError(try LedgerBackup(
            ledger: ledger,
            classificationRules: [first, second]
        ).validateForRestore()) { error in
            XCTAssertEqual(
                error as? LedgerBackupValidationError,
                .duplicateClassificationRuleID(ruleID)
            )
        }
    }

    func testHistoricalArchivedBudgetAndStaleRuleRemainRestorable() throws {
        var ledger = Ledger()
        let groceries = Account(name: "Old groceries", kind: .expense, status: .archived)
        ledger.addAccount(groceries)

        let historicalTarget = BudgetTarget(
            accountID: groceries.id,
            amount: Money(100, currency: eur),
            effectiveFrom: BudgetPeriod(year: 2024, month: 1),
            effectiveUntil: BudgetPeriod(year: 2024, month: 12)
        )
        let staleRule = ClassificationRuleConfiguration(
            needle: "OLD SHOP",
            counterpartyAccountID: AccountID()
        )
        let backup = LedgerBackup(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            ledger: ledger,
            budget: Budget(targets: [historicalTarget]),
            classificationRules: [staleRule]
        )

        XCTAssertNoThrow(try backup.validateForRestore())
        let restored = try LedgerBackupCoder.decode(LedgerBackupCoder.encode(backup))
        XCTAssertEqual(restored, backup)
    }

    func testBackupDecoderRejectsNonpositiveAndFutureFormatVersions() throws {
        for version in [0, LedgerBackup.currentFormatVersion + 1] {
            let backup = LedgerBackup(formatVersion: version, ledger: Ledger())
            let data = try LedgerBackupCoder.encode(backup)
            XCTAssertThrowsError(try LedgerBackupCoder.decode(data)) { error in
                XCTAssertEqual(error as? LedgerBackupError, .unsupportedFormatVersion(version))
            }
        }
    }
}
