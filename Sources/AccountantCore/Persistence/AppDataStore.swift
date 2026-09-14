import Foundation

/// All financial data read at one boundary. Partial data is display-only while
/// `damage` is nonempty; callers must refuse ordinary mutations and saving.
public struct AppDataLoadResult: Sendable {
    public let data: LedgerBackup
    public let damage: [QuarantineRecord]

    public init(data: LedgerBackup, damage: [QuarantineRecord] = []) {
        self.data = data
        self.damage = damage
    }
}

/// A single authoritative financial snapshot at the existing ledger path.
/// Version 5 requires ledger, budget and rules together. Versions 1...4 still
/// read their companion files; the first save replaces the envelope atomically.
/// Once version 5 is present, companion files and their markers are never read.
/// An older app rejects version 5 instead of reopening stale companion data.
public struct AppDataStore: Sendable {
    public let directory: URL
    private let checkpoint: @Sendable (Checkpoint) throws -> Void

    /// Fault boundaries in the production write path. No-op unless injected by
    /// tests. `afterCommit` models termination after replacement but before its
    /// caller observes success; it is not a rollback point.
    public enum Checkpoint: String, CaseIterable, Sendable {
        case beforeEncoding, beforeCommit, afterCommit, beforeRecoveryCompletion, afterRecoveryCompletion
    }

    public init(directory: URL) {
        self.init(directory: directory, checkpoint: { _ in })
    }

    public init(directory: URL, checkpoint: @escaping @Sendable (Checkpoint) throws -> Void) {
        self.directory = directory
        self.checkpoint = checkpoint
    }

    private var ledgerURL: URL { directory.appendingPathComponent("ledger.json") }

    private var store: JSONFileStore<StoredAppData> {
        let checkpoint = checkpoint
        return JSONFileStore(
            fileURL: ledgerURL,
            fallback: { StoredAppData(data: LedgerBackup(ledger: Ledger())) },
            encode: { value in
                try checkpoint(.beforeEncoding)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                LedgerDateCoding.apply(to: encoder)
                return try encoder.encode(value)
            },
            decode: { bytes in
                let decoder = JSONDecoder()
                LedgerDateCoding.apply(to: decoder)
                return try decoder.decode(StoredAppData.self, from: bytes)
            },
            writeData: { bytes, url in
                try checkpoint(.beforeCommit)
                try bytes.write(to: url, options: .atomic)
                try checkpoint(.afterCommit)
            }
        )
    }

    public func load() -> AppDataLoadResult {
        var damage: [QuarantineRecord] = []
        var ledger = Ledger()
        switch store.loadOutcome() {
        case let .loaded(stored):
            if !stored.isLegacy { return AppDataLoadResult(data: stored.data) }
            ledger = stored.data.ledger
        case .empty:
            if case .resolved = FileQuarantine.state(for: ledgerURL) {
                // A resolved recovery promises a replacement exists. Losing it
                // is not a first install and cannot revive old companions.
                damage.append(FileQuarantine.legacyRecord(for: ledgerURL) ?? QuarantineRecord(
                    originalURL: ledgerURL, quarantinedURL: ledgerURL,
                    reason: "The saved replacement is missing. Restore a backup or start fresh."
                ))
            }
        case let .unreadable(record): damage.append(record)
        }

        // Legacy companions are read only to migrate an old ledger or display
        // recoverable data while the primary store is protected. They can never
        // authorize editing after a primary read failure.
        let budgetURL = directory.appendingPathComponent("budget.json")
        let rulesURL = directory.appendingPathComponent("classification-rules.json")
        var budget = Budget()
        var rules: [ClassificationRuleConfiguration] = []
        switch JSONFileStore(fileURL: budgetURL, fallback: { Budget() }).loadOutcome() {
        case let .loaded(value): budget = value
        case .empty: break
        case let .unreadable(record): damage.append(record)
        }
        switch JSONFileStore(fileURL: rulesURL, fallback: { [ClassificationRuleConfiguration]() }).loadOutcome() {
        case let .loaded(value): rules = value
        case .empty: break
        case let .unreadable(record): damage.append(record)
        }
        let data = LedgerBackup(ledger: ledger, budget: budget, classificationRules: rules)
        if damage.isEmpty {
            do { try data.validateForRestore() }
            catch {
                // The files decode individually but do not form valid financial
                // data together. Protect their original bytes before offering
                // recovery, including the otherwise-readable primary ledger.
                damage = [ledgerURL, budgetURL, rulesURL]
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                    .map { url in
                        let reason = "Saved data is inconsistent: \(error)"
                        do { return try FileQuarantine.beginRecovery(for: url, reason: reason) }
                        catch {
                            return QuarantineRecord(originalURL: url, quarantinedURL: url, reason: reason)
                        }
                    }
            }
        }
        return AppDataLoadResult(data: data, damage: damage)
    }

    public func save(_ data: LedgerBackup) throws {
        try data.validateForRestore()
        guard load().damage.isEmpty else { throw StoreRecoveryError.recoveryUnresolved }
        try store.save(StoredAppData(data: data))
    }

    public func replaceForRecovery(_ data: LedgerBackup) throws {
        try data.validateForRestore()
        // Protect any unreadable originals even when called without a prior
        // load. Only the ledger path is replaced; companions remain untouched.
        let loaded = load()
        if !loaded.damage.isEmpty, FileManager.default.fileExists(atPath: ledgerURL.path) {
            switch FileQuarantine.state(for: ledgerURL) {
            case .absent, .resolved:
                // A companion may be damaged while the primary still decodes.
                // Preserve that primary too: it supplies the accounts/history
                // needed to recover the old set. A failed marker write throws
                // here rather than falling through to an ordinary overwrite.
                _ = try FileQuarantine.beginRecovery(
                    for: ledgerURL, reason: "Replacing protected financial data"
                )
            case .unresolved, .invalid:
                break // The store's replacement checks enforce these markers.
            }
        }
        try store.replaceForRecovery(StoredAppData(data: data))
    }

    public func completeRecovery() throws {
        try checkpoint(.beforeRecoveryCompletion)
        try store.completeRecovery()
        try checkpoint(.afterRecoveryCompletion)
    }
}

private struct StoredAppData: Codable, Sendable {
    static let schemaVersion = 5
    let data: LedgerBackup
    let isLegacy: Bool

    init(data: LedgerBackup) {
        self.data = data
        self.isLegacy = false
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, savedAt, ledger, budget, classificationRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        if (1...PersistedLedger.currentSchemaVersion).contains(version) {
            let legacy = try PersistedLedger(from: decoder)
            try legacy.ledger.validate()
            data = LedgerBackup(createdAt: legacy.savedAt, ledger: legacy.ledger)
            isLegacy = true
        } else {
            guard version == Self.schemaVersion else {
                throw LedgerStoreError.unsupportedSchemaVersion(version)
            }
            // Unlike portable backups, persisted snapshots require every field.
            // A missing budget or rules array cannot quietly become emptiness.
            data = LedgerBackup(
                createdAt: try container.decode(Date.self, forKey: .savedAt),
                ledger: try container.decode(Ledger.self, forKey: .ledger),
                budget: try container.decode(Budget.self, forKey: .budget),
                classificationRules: try container.decode([ClassificationRuleConfiguration].self,
                                                         forKey: .classificationRules)
            )
            try data.validateForRestore()
            isLegacy = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(data.createdAt, forKey: .savedAt)
        try container.encode(data.ledger, forKey: .ledger)
        try container.encode(data.budget, forKey: .budget)
        try container.encode(data.classificationRules, forKey: .classificationRules)
    }
}
