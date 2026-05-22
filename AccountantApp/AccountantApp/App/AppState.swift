import Foundation
import AccountantCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published private(set) var isLoading: Bool
    @Published var lastError: AppError?

    private let repository: LedgerRepository
    private var didAttemptInitialLoad = false

    init(repository: LedgerRepository) {
        self.repository = repository
        self.ledger = Ledger()
        self.isLoading = false
        self.lastError = nil
    }

    func loadIfNeeded() async {
        guard !didAttemptInitialLoad else { return }

        didAttemptInitialLoad = true
        isLoading = true
        defer { isLoading = false }

        do {
            ledger = try await repository.loadOrCreate()
            lastError = nil
        } catch {
            ledger = Ledger()
            lastError = AppError(error)
        }
    }

    @discardableResult
    func save() async -> Bool {
        do {
            try await repository.save(ledger)
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
    }

    @discardableResult
    private func mutateAndSave(_ mutate: (inout Ledger) throws -> Void) async -> Bool {
        var updated = ledger

        do {
            try mutate(&updated)
            try await repository.save(updated)
            ledger = updated
            lastError = nil
            return true
        } catch {
            lastError = AppError(error)
            return false
        }
    }

    @discardableResult
    func createAccount(name: String, kind: AccountKind) async -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedName.isEmpty else {
            lastError = AppError(message: "Account name cannot be empty.")
            return false
        }

        return await mutateAndSave { ledger in
            ledger.addAccount(Account(name: cleanedName, kind: kind))
        }
    }

    @discardableResult
    func renameAccount(id: AccountID, to newName: String) async -> Bool {
        let cleanedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedName.isEmpty else {
            lastError = AppError(message: "Account name cannot be empty.")
            return false
        }

        return await mutateAndSave { ledger in
            try ledger.renameAccount(id: id, to: cleanedName)
        }
    }

    @discardableResult
    func archiveAccount(id: AccountID) async -> Bool {
        await mutateAndSave { ledger in
            try ledger.archiveAccount(id: id)
        }
    }

    @discardableResult
    func restoreAccount(id: AccountID) async -> Bool {
        await mutateAndSave { ledger in
            try ledger.restoreAccount(id: id)
        }
    }
}
