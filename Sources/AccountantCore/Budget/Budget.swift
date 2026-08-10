import Foundation

public struct BudgetTargetID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum BudgetError: Error, Equatable, Sendable {
    case nonPositiveAmount(Money)
    case unknownAccount(AccountID)
    case accountNotBudgetable(AccountID)
    case overlappingTarget(accountID: AccountID, existing: BudgetTargetID)
}

/// A monthly limit for one category, effective over a range of months.
///
/// Ranged rather than one row per month so that raising a grocery budget in March
/// does not require rewriting every month before or after it — and so history stays
/// honest: what you *had* planned in January is still recoverable in June.
public struct BudgetTarget: Hashable, Codable, Sendable {
    public let id: BudgetTargetID

    /// The category this limits. An expense account in practice.
    public var accountID: AccountID

    /// The monthly limit. Always positive: a limit of "minus fifty euros" is not
    /// a thing a person means.
    public var amount: Money

    public var effectiveFrom: BudgetPeriod

    /// Last month this applies to, inclusive. `nil` means ongoing.
    public var effectiveUntil: BudgetPeriod?

    public init(
        id: BudgetTargetID = BudgetTargetID(),
        accountID: AccountID,
        amount: Money,
        effectiveFrom: BudgetPeriod,
        effectiveUntil: BudgetPeriod? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
    }

    public func applies(to period: BudgetPeriod) -> Bool {
        guard period >= effectiveFrom else { return false }
        guard let effectiveUntil else { return true }
        return period <= effectiveUntil
    }
}

/// The set of targets a person has set.
///
/// Deliberately not part of `Ledger`. A budget is an intention, not an accounting
/// fact — it moves no money and changes no balance. Keeping it out preserves the
/// property that everything in the ledger actually happened.
public struct Budget: Hashable, Codable, Sendable {
    public private(set) var targets: [BudgetTarget]

    public init(targets: [BudgetTarget] = []) {
        self.targets = targets
    }

    // MARK: - Reading

    /// The target governing an account in a given month, if any.
    public func target(for accountID: AccountID, in period: BudgetPeriod) -> BudgetTarget? {
        targets.first { $0.accountID == accountID && $0.applies(to: period) }
    }

    /// Every target in force for a month, ordered deterministically by account.
    public func targets(in period: BudgetPeriod) -> [BudgetTarget] {
        targets
            .filter { $0.applies(to: period) }
            .sorted { $0.accountID.rawValue.uuidString < $1.accountID.rawValue.uuidString }
    }

    public var budgetedAccountIDs: Set<AccountID> {
        Set(targets.map(\.accountID))
    }

    // MARK: - Writing

    /// Sets the monthly limit for a category from `period` onward.
    ///
    /// Changing an amount closes the previous target at the preceding month rather
    /// than editing it, so a past month keeps reporting against the limit that was
    /// actually in force at the time.
    public mutating func setTarget(
        amount: Money,
        for accountID: AccountID,
        from period: BudgetPeriod,
        in ledger: Ledger
    ) throws {
        guard amount.amount > .zero else {
            throw BudgetError.nonPositiveAmount(amount)
        }

        guard let account = ledger.accounts[accountID] else {
            throw BudgetError.unknownAccount(accountID)
        }

        guard account.kind.isBudgetable else {
            throw BudgetError.accountNotBudgetable(accountID)
        }

        closeOpenTargets(for: accountID, before: period)

        targets.append(
            BudgetTarget(
                accountID: accountID,
                amount: amount,
                effectiveFrom: period
            )
        )
    }

    /// Stops budgeting a category from `period` onward, leaving history intact.
    public mutating func removeTarget(for accountID: AccountID, from period: BudgetPeriod) {
        closeOpenTargets(for: accountID, before: period)
    }

    /// Forgets a category entirely, including its history. For when an account was
    /// budgeted by mistake.
    public mutating func forget(accountID: AccountID) {
        targets.removeAll { $0.accountID == accountID }
    }

    /// Ends any target for this account that would otherwise still be running at
    /// `period`, and discards ones that would start at or after it.
    private mutating func closeOpenTargets(for accountID: AccountID, before period: BudgetPeriod) {
        // A target starting at or after the new one never applied to anything.
        targets.removeAll { $0.accountID == accountID && $0.effectiveFrom >= period }

        for index in targets.indices where targets[index].accountID == accountID {
            let stillRunning = targets[index].effectiveUntil.map { $0 >= period } ?? true

            if stillRunning {
                targets[index].effectiveUntil = period.previous
            }
        }
    }
}

public extension AccountKind {
    /// Whether a monthly limit is meaningful for this kind of account.
    ///
    /// Only spending categories. Budgeting an asset account would be a category
    /// error — a bank account holds a balance, it does not have a monthly allowance.
    var isBudgetable: Bool {
        self == .expense
    }
}
