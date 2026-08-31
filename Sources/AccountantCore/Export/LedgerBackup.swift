import Foundation

/// Everything the app would need to become itself again.
///
/// The ledger file alone is not that. Budget limits and import rules live in
/// their own files, and a "backup" holding only one of the three restores an app
/// with your transactions and none of your plan. So this carries all three in one
/// document, which is also what makes it a single thing to hand to someone or
/// drop into a cloud folder.
///
/// `formatVersion` is separate from the ledger's own `schemaVersion` on purpose.
/// They change for different reasons — one when the backup envelope gains a
/// field, the other when the accounting model does — and collapsing them would
/// mean a change to either invalidating files affected by neither.
public struct LedgerBackup: Codable, Sendable, Equatable {

    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let createdAt: Date
    public let ledger: Ledger
    public let budget: Budget
    public let classificationRules: [ClassificationRuleConfiguration]

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        createdAt: Date = Date(),
        ledger: Ledger,
        budget: Budget = Budget(),
        classificationRules: [ClassificationRuleConfiguration] = []
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.ledger = ledger
        self.budget = budget
        self.classificationRules = classificationRules
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, createdAt, ledger, budget, classificationRules
    }

    /// Tolerant of a backup missing the pieces that are allowed to be absent.
    ///
    /// A file with no budget and no rules is a perfectly good backup of an app
    /// where neither had been used, and refusing it would be refusing a valid
    /// restore over a technicality.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.ledger = try container.decode(Ledger.self, forKey: .ledger)
        self.budget = try container.decodeIfPresent(Budget.self, forKey: .budget) ?? Budget()
        self.classificationRules = try container.decodeIfPresent(
            [ClassificationRuleConfiguration].self,
            forKey: .classificationRules
        ) ?? []
    }
}

/// What a backup file says about itself, without committing to restoring it.
///
/// Restoring replaces everything, so the one thing the user must be able to do
/// first is check they picked the right file. Counts and a date answer that;
/// "1 account, 0 transactions" is a mis-picked file and you can see it before
/// anything is overwritten.
public struct LedgerBackupSummary: Sendable, Equatable {
    public let createdAt: Date
    public let accountCount: Int
    public let transactionCount: Int
    public let draftCount: Int
    public let budgetTargetCount: Int
    public let classificationRuleCount: Int

    public init(backup: LedgerBackup) {
        self.createdAt = backup.createdAt
        self.accountCount = backup.ledger.accounts.count
        self.transactionCount = backup.ledger.transactions.count
        self.draftCount = backup.ledger.transactions.count { $0.state == .draft }
        self.budgetTargetCount = backup.budget.targets.count
        self.classificationRuleCount = backup.classificationRules.count
    }
}

public enum LedgerBackupError: Error, Equatable, LocalizedError {
    /// Written by a newer version of the app than this one.
    case unsupportedFormatVersion(Int)

    /// Not a backup file, or damaged.
    case unreadable

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormatVersion(version):
            "This backup was made by a newer version of the app (format \(version)). Update the app and try again."
        case .unreadable:
            "This file is not an Accountant backup, or it is damaged."
        }
    }
}

/// Reads and writes backup documents.
public enum LedgerBackupCoder {

    public static func encode(_ backup: LedgerBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        LedgerDateCoding.apply(to: encoder)

        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> LedgerBackup {
        let decoder = JSONDecoder()
        LedgerDateCoding.apply(to: decoder)

        let backup: LedgerBackup

        do {
            backup = try decoder.decode(LedgerBackup.self, from: data)
        } catch {
            throw LedgerBackupError.unreadable
        }

        // Checked after decoding rather than by peeking at the version first: a
        // newer file may well decode fine, and the honest reason to refuse it is
        // that this app does not know what it might mean, not that it choked.
        guard backup.formatVersion <= LedgerBackup.currentFormatVersion else {
            throw LedgerBackupError.unsupportedFormatVersion(backup.formatVersion)
        }

        return backup
    }

    /// Reads just enough to describe the file.
    public static func summarize(_ data: Data) throws -> LedgerBackupSummary {
        LedgerBackupSummary(backup: try decode(data))
    }
}
