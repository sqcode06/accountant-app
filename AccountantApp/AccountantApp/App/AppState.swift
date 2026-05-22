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

    func createAccount(name: String, kind: AccountKind) async {
        var updated = ledger
        updated.addAccount(Account(name: name, kind: kind))

        do {
            try await repository.save(updated)
            ledger = updated
            lastError = nil
        } catch {
            lastError = AppError(error)
        }
    }
}
