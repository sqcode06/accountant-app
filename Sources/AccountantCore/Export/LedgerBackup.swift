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

    /// Checks a backup immediately before it is allowed to replace live data.
    ///
    /// `LedgerBackupCoder.decode` calls this automatically. It is public as well
    /// because tests and app integrations can construct a `LedgerBackup` directly,
    /// bypassing the document decoder.
    public func validateForRestore() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw LedgerBackupError.unsupportedFormatVersion(formatVersion)
        }

        try ledger.validate()
        try validateBudget()
        try validateClassificationRuleIdentities()
    }

    private func validateBudget() throws {
        var targetIDs = Set<BudgetTargetID>()
        var targetsByAccount: [AccountID: [BudgetTarget]] = [:]

        for target in budget.targets {
            guard target.id.rawValue != Self.nilUUID else {
                throw LedgerBackupValidationError.invalidBudgetTargetID(target.id)
            }
            guard targetIDs.insert(target.id).inserted else {
                throw LedgerBackupValidationError.duplicateBudgetTargetID(target.id)
            }
            guard !target.amount.amount.isNaN, target.amount.amount > .zero else {
                throw LedgerBackupValidationError.invalidBudgetAmount(target.id)
            }
            guard target.amount.currency.hasValidCode else {
                throw LedgerError.invalidCurrencyCode(target.amount.currency.code)
            }
            guard target.effectiveFrom.month >= 1, target.effectiveFrom.month <= 12,
                  target.effectiveUntil.map({ $0.month >= 1 && $0.month <= 12 }) ?? true,
                  target.effectiveUntil.map({ $0 >= target.effectiveFrom }) ?? true else {
                throw LedgerBackupValidationError.invalidBudgetRange(target.id)
            }
            guard let account = ledger.accounts[target.accountID] else {
                throw LedgerBackupValidationError.unknownBudgetAccount(target.accountID)
            }
            guard account.kind.isBudgetable else {
                throw LedgerBackupValidationError.accountNotBudgetable(target.accountID)
            }

            targetsByAccount[target.accountID, default: []].append(target)
        }

        for targets in targetsByAccount.values {
            let ordered = targets.sorted { $0.effectiveFrom < $1.effectiveFrom }
            for (earlier, later) in zip(ordered, ordered.dropFirst()) {
                if earlier.effectiveUntil.map({ $0 >= later.effectiveFrom }) ?? true {
                    throw LedgerBackupValidationError.overlappingBudgetTargets(
                        accountID: earlier.accountID,
                        first: earlier.id,
                        second: later.id
                    )
                }
            }
        }
    }

    private func validateClassificationRuleIdentities() throws {
        var ruleIDs = Set<UUID>()

        for rule in classificationRules {
            guard rule.id != Self.nilUUID else {
                throw LedgerBackupValidationError.invalidClassificationRuleID(rule.id)
            }
            guard ruleIDs.insert(rule.id).inserted else {
                throw LedgerBackupValidationError.duplicateClassificationRuleID(rule.id)
            }
            if let accountID = rule.counterpartyAccountID,
               accountID.rawValue == Self.nilUUID {
                throw LedgerBackupValidationError.invalidClassificationAccountID(accountID)
            }
        }

        // A nonzero rule reference may be stale after "Remove unused accounts".
        // The app deliberately retains that rule and filters it at use time, so
        // rejecting such backups would strand a supported historical state.
    }

    private static let nilUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

public enum LedgerBackupValidationError: Error, Equatable, Sendable {
    case invalidBudgetTargetID(BudgetTargetID)
    case duplicateBudgetTargetID(BudgetTargetID)
    case invalidBudgetAmount(BudgetTargetID)
    case invalidBudgetRange(BudgetTargetID)
    case unknownBudgetAccount(AccountID)
    case accountNotBudgetable(AccountID)
    case overlappingBudgetTargets(
        accountID: AccountID,
        first: BudgetTargetID,
        second: BudgetTargetID
    )
    case invalidClassificationRuleID(UUID)
    case duplicateClassificationRuleID(UUID)
    case invalidClassificationAccountID(AccountID)
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

        do {
            try backup.validateForRestore()
        } catch let error as LedgerBackupError {
            throw error
        } catch {
            throw LedgerBackupError.unreadable
        }

        return backup
    }

    /// Reads just enough to describe the file.
    public static func summarize(_ data: Data) throws -> LedgerBackupSummary {
        LedgerBackupSummary(backup: try decode(data))
    }
}
