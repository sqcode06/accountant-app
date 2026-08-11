import Foundation
import AccountantCore

protocol BudgetRepository: Sendable {
    func loadOrCreate() async throws -> Budget
    func save(_ budget: Budget) async throws

    /// See `LedgerRepository.load()` — same reason, same shape.
    func load() async -> StoreLoadOutcome<Budget>
}

extension BudgetRepository {
    func load() async -> StoreLoadOutcome<Budget> {
        guard let budget = try? await loadOrCreate() else { return .empty }
        return .loaded(budget)
    }
}

/// Stored beside the ledger rather than inside it, mirroring where budgets sit in
/// the core: an intention is not an accounting fact, so it does not belong in the
/// file that records what happened.
struct LocalJSONBudgetRepository: BudgetRepository {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func live() -> LocalJSONBudgetRepository {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let appDirectory = baseDirectory.appendingPathComponent(
            "Accountant",
            isDirectory: true
        )

        return LocalJSONBudgetRepository(
            fileURL: appDirectory.appendingPathComponent("budget.json")
        )
    }

    private var store: JSONFileStore<Budget> {
        JSONFileStore(fileURL: fileURL) { Budget() }
    }

    func loadOrCreate() async throws -> Budget {
        switch await load() {
        case let .loaded(budget): return budget
        case .empty, .unreadable: return Budget()
        }
    }

    /// The safe path — quarantines an unreadable file instead of silently
    /// starting empty and overwriting it on the next save.
    func load() async -> StoreLoadOutcome<Budget> {
        let store = store

        return await Task.detached(priority: .utility) {
            store.loadOutcome()
        }.value
    }

    func save(_ budget: Budget) async throws {
        let fileURL = fileURL

        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            try encoder.encode(budget).write(to: fileURL, options: [.atomic])
        }.value
    }
}

struct EmptyBudgetRepository: BudgetRepository {
    func loadOrCreate() async throws -> Budget { Budget() }
    func save(_ budget: Budget) async throws {}
}
