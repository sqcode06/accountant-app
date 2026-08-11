import Foundation
import AccountantCore

protocol BudgetRepository: Sendable {
    func loadOrCreate() async throws -> Budget
    func save(_ budget: Budget) async throws
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

    func loadOrCreate() async throws -> Budget {
        let fileURL = fileURL

        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return Budget()
            }

            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Budget.self, from: data)
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
