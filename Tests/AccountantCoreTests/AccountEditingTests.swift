import XCTest
@testable import AccountantCore

/// Renaming accounts and deleting drafts.
///
/// Both are live paths — a rename from the account editor, a swipe-to-delete in
/// review — and both reached this branch with no coverage in the package tests.
/// The rename had some in the Xcode-only app target, which never runs on Linux or
/// in CI; the draft delete had none anywhere.
final class AccountEditingTests: XCTestCase {

    private let eur = Currency("EUR")

    private func makeLedger() -> (ledger: Ledger, bank: Account, groceries: Account) {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)

        ledger.addAccount(bank)
        ledger.addAccount(groceries)

        return (ledger, bank, groceries)
    }

    private func makeDraft(
        in ledger: inout Ledger,
        bank: Account,
        groceries: Account,
        amount: Int = 10
    ) throws -> Transaction {
        let draft = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(amount), currency: eur),
            date: Date(timeIntervalSince1970: 1_000)
        )

        try ledger.addTransaction(draft)
        return draft
    }

    // MARK: - Renaming

    func testRenamingChangesOnlyTheName() throws {
        var (ledger, bank, _) = makeLedger()

        try ledger.renameAccount(id: bank.id, to: "LHV")

        let renamed = try XCTUnwrap(ledger.accounts[bank.id])
        XCTAssertEqual(renamed.name, "LHV")

        // Everything else about the account has to survive a rename, or renaming
        // an account would quietly change what its balance means.
        XCTAssertEqual(renamed.id, bank.id)
        XCTAssertEqual(renamed.kind, .asset)
        XCTAssertEqual(renamed.currency, eur)
        XCTAssertEqual(renamed.status, .active)
    }

    func testRenamingKeepsHistoryAttached() throws {
        var (ledger, bank, groceries) = makeLedger()
        _ = try makeDraft(in: &ledger, bank: bank, groceries: groceries, amount: 25)

        try ledger.renameAccount(id: bank.id, to: "Renamed")

        // Postings reference the account by ID, so the balance must be untouched.
        XCTAssertEqual(
            ledger.balance(of: bank.id, currency: eur).amount,
            Decimal(-25)
        )
    }

    func testRenamingAnArchivedAccountIsAllowed() throws {
        var (ledger, bank, _) = makeLedger()
        try ledger.archiveAccount(id: bank.id)

        try ledger.renameAccount(id: bank.id, to: "Old current account")

        let renamed = try XCTUnwrap(ledger.accounts[bank.id])
        XCTAssertEqual(renamed.name, "Old current account")
        XCTAssertEqual(renamed.status, .archived)
    }

    func testRenamingAnUnknownAccountThrows() throws {
        var (ledger, _, _) = makeLedger()
        let stranger = Account(name: "Not added", kind: .asset)

        XCTAssertThrowsError(try ledger.renameAccount(id: stranger.id, to: "Nope")) { error in
            guard case LedgerError.accountNotFound(let id) = error else {
                return XCTFail("Expected accountNotFound, got \(error)")
            }

            XCTAssertEqual(id, stranger.id)
        }
    }

    func testRenamingToADuplicateNameIsAllowed() throws {
        var (ledger, bank, groceries) = makeLedger()

        // Names are labels, not identity. Two accounts may legitimately share one
        // — "Savings" at two banks — and the ledger keys everything by ID.
        try ledger.renameAccount(id: groceries.id, to: bank.name)

        XCTAssertEqual(ledger.accounts[groceries.id]?.name, "Swedbank")
        XCTAssertEqual(ledger.accounts[bank.id]?.name, "Swedbank")
        XCTAssertEqual(ledger.accounts.count, 2)
    }

    /// The core deliberately does not trim or reject blank names.
    ///
    /// Documenting the boundary rather than the behaviour: `AppState.renameAccount`
    /// trims and refuses an empty result, so nothing in the app can reach this. If
    /// that guard is ever removed, this test says where the responsibility sat.
    func testCoreDoesNotValidateNameContent() throws {
        var (ledger, bank, _) = makeLedger()

        try ledger.renameAccount(id: bank.id, to: "   ")

        XCTAssertEqual(ledger.accounts[bank.id]?.name, "   ")
    }

    // MARK: - Deleting drafts

    func testDeletingADraftRemovesItAndItsEffectOnBalances() throws {
        var (ledger, bank, groceries) = makeLedger()
        let draft = try makeDraft(in: &ledger, bank: bank, groceries: groceries, amount: 30)

        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(-30))

        try ledger.deleteDraftTransaction(id: draft.id)

        XCTAssertTrue(ledger.transactions.isEmpty)
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, .zero)
        XCTAssertEqual(ledger.balance(of: groceries.id, currency: eur).amount, .zero)
    }

    func testDeletingADraftLeavesOtherTransactionsAlone() throws {
        var (ledger, bank, groceries) = makeLedger()
        let keep = try makeDraft(in: &ledger, bank: bank, groceries: groceries, amount: 10)
        let drop = try makeDraft(in: &ledger, bank: bank, groceries: groceries, amount: 40)

        try ledger.deleteDraftTransaction(id: drop.id)

        XCTAssertEqual(ledger.transactions.map(\.id), [keep.id])
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(-10))
    }

    /// Finalizing is one way. A confirmed entry is a record, not a draft.
    func testDeletingAFinalizedTransactionThrows() throws {
        var (ledger, bank, groceries) = makeLedger()
        let draft = try makeDraft(in: &ledger, bank: bank, groceries: groceries)
        try ledger.finalizeTransaction(id: draft.id)

        XCTAssertThrowsError(try ledger.deleteDraftTransaction(id: draft.id)) { error in
            guard case LedgerError.transactionFinalized(let id) = error else {
                return XCTFail("Expected transactionFinalized, got \(error)")
            }

            XCTAssertEqual(id, draft.id)
        }

        // And the refusal must not have removed it on the way out.
        XCTAssertEqual(ledger.transactions.count, 1)
        XCTAssertEqual(ledger.balance(of: bank.id, currency: eur).amount, Decimal(-10))
    }

    func testDeletingAnUnknownTransactionThrows() throws {
        var (ledger, bank, groceries) = makeLedger()
        let draft = try makeDraft(in: &ledger, bank: bank, groceries: groceries)
        try ledger.deleteDraftTransaction(id: draft.id)

        XCTAssertThrowsError(try ledger.deleteDraftTransaction(id: draft.id))
        XCTAssertTrue(ledger.transactions.isEmpty)
    }

    /// Deleting a draft must not take its accounts with it.
    func testDeletingADraftKeepsTheAccounts() throws {
        var (ledger, bank, groceries) = makeLedger()
        let draft = try makeDraft(in: &ledger, bank: bank, groceries: groceries)

        try ledger.deleteDraftTransaction(id: draft.id)

        XCTAssertEqual(ledger.accounts.count, 2)
        XCTAssertNotNil(ledger.accounts[bank.id])
        XCTAssertNotNil(ledger.accounts[groceries.id])
    }

    func testDeletingADraftUnblocksArchivingItsAccount() throws {
        var (ledger, bank, groceries) = makeLedger()
        let draft = try makeDraft(in: &ledger, bank: bank, groceries: groceries)

        // An account with an unreviewed draft against it cannot be archived.
        XCTAssertThrowsError(try ledger.archiveAccount(id: bank.id))

        try ledger.deleteDraftTransaction(id: draft.id)

        XCTAssertNoThrow(try ledger.archiveAccount(id: bank.id))
        XCTAssertEqual(ledger.accounts[bank.id]?.status, .archived)
    }
}
