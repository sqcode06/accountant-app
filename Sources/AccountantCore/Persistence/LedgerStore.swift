import Foundation

public enum LedgerStoreError: Error, Equatable {
    case fileNotFound
    case unsupportedSchemaVersion(Int)
}

/// What was found on disk.
///
/// Replaces a `throws` that collapsed two very different situations into one.
/// "There is no file yet" and "there is a file and I cannot read it" both used to
/// arrive as an error, and every caller treated the pair as "start empty" — which
/// meant the next save wrote an empty document over real data.
public enum StoreLoadOutcome<Value: Sendable>: Sendable {
    /// A file was there and decoded.
    case loaded(Value)

    /// No file yet. An ordinary first run; safe to start empty and save freely.
    case empty

    /// A file was there and could not be read. Its bytes are protected by a
    /// durable recovery record; when moving them aside failed they remain at the
    /// original path and writes stay blocked.
    ///
    /// Callers **must not** write to the store after receiving this. Starting
    /// empty here is what destroys data.
    case unreadable(QuarantineRecord)
}

public typealias LedgerLoadOutcome = StoreLoadOutcome<Ledger>

public protocol LedgerStore: Sendable {
    func load() throws -> Ledger
    func save(_ ledger: Ledger) throws

    /// Reads the store, distinguishing "nothing yet" from "damaged".
    ///
    /// Deliberately non-throwing: every failure is a case of the result, so there
    /// is no error for a caller to swallow with `try?` and no way to accidentally
    /// treat damage as emptiness.
    func loadOutcome() -> LedgerLoadOutcome
}

public struct JSONLedgerStore: LedgerStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        LedgerDateCoding.apply(to: enc)
        self.encoder = enc

        let dec = JSONDecoder()
        LedgerDateCoding.apply(to: dec)
        self.decoder = dec
    }

    /// True when an unfinished recovery, a malformed sidecar, or an unadopted
    /// legacy quarantine prevents normal writes.
    public var hasUnresolvedRecovery: Bool {
        switch FileQuarantine.state(for: fileURL) {
        case .unresolved, .invalid:
            return true
        case .absent:
            return FileQuarantine.legacyRecord(for: fileURL) != nil
        case .resolved:
            return false
        }
    }

    public func load() throws -> Ledger {
        switch FileQuarantine.state(for: fileURL) {
        case .unresolved:
            throw StoreRecoveryError.recoveryUnresolved
        case .invalid:
            throw StoreRecoveryError.recoveryRecordUnreadable
        case .absent where FileQuarantine.legacyRecord(for: fileURL) != nil:
            throw StoreRecoveryError.recoveryUnresolved
        case .absent, .resolved:
            break
        }
        return try readLedger()
    }

    private func readLedger() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LedgerStoreError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        let persisted = try decoder.decode(PersistedLedger.self, from: data)

        guard persisted.schemaVersion <= PersistedLedger.currentSchemaVersion else {
            throw LedgerStoreError.unsupportedSchemaVersion(persisted.schemaVersion)
        }

        return persisted.ledger
    }

    public func loadOutcome() -> LedgerLoadOutcome {
        switch FileQuarantine.state(for: fileURL) {
        case let .unresolved(marker):
            return .unreadable(FileQuarantine.record(from: marker, for: fileURL))
        case .invalid:
            return .unreadable(unreadableSidecarRecord())
        case .absent:
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return legacyOutcomeOrEmpty()
            }
        case .resolved:
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return .empty
            }
        }

        do {
            return .loaded(try readLedger())
        } catch {
            return quarantineFailure(reason: String(describing: error))
        }
    }

    public func save(_ ledger: Ledger) throws {
        try ensureOrdinarySaveIsSafe()
        try write(ledger)
    }

    /// Writes a replacement while keeping the recovery record unresolved. This
    /// lets a coordinator replace every store before any becomes loadable again.
    /// On a healthy or first-run store this is equivalent to `save(_:)`.
    public func replaceForRecovery(_ ledger: Ledger) throws {
        switch FileQuarantine.state(for: fileURL) {
        case let .unresolved(marker):
            guard FileQuarantine.canReplace(marker, for: fileURL) else {
                throw StoreRecoveryError.originalNotSafelyQuarantined
            }
        case .invalid:
            throw StoreRecoveryError.recoveryRecordUnreadable
        case .absent:
            if let legacy = FileQuarantine.legacyRecord(for: fileURL) {
                do {
                    let marker = try FileQuarantine.adoptLegacyRecovery(legacy, for: fileURL)
                    guard FileQuarantine.canReplace(marker, for: fileURL) else {
                        throw StoreRecoveryError.originalNotSafelyQuarantined
                    }
                } catch let error as StoreRecoveryError {
                    throw error
                } catch {
                    throw StoreRecoveryError.recoveryRecordUnreadable
                }
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                // A failed initial sidecar write leaves a corrupt original here.
                // Never let the recovery API overwrite it merely because no
                // durable marker was possible at that instant.
                do {
                    _ = try load()
                } catch {
                    throw StoreRecoveryError.originalNotSafelyQuarantined
                }
            }
        case .resolved:
            try ensureExistingResolvedFileIsValid()
        }
        try write(ledger)
    }

    /// Validates a replacement before resolving the sidecar. It is a no-op for a
    /// healthy store so callers can complete all stores as one coordinated step.
    public func completeRecovery() throws {
        switch FileQuarantine.state(for: fileURL) {
        case .absent:
            return
        case .resolved:
            try ensureExistingResolvedFileIsValid()
        case .invalid:
            throw StoreRecoveryError.recoveryRecordUnreadable
        case let .unresolved(marker):
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw StoreRecoveryError.replacementMissing
            }
            do {
                _ = try readLedger()
            } catch {
                throw StoreRecoveryError.replacementUnreadable
            }
            do {
                try FileQuarantine.resolve(marker, for: fileURL)
            } catch {
                throw StoreRecoveryError.recoveryRecordUnreadable
            }
        }
    }

    private func write(_ ledger: Ledger) throws {
        let persisted = PersistedLedger(ledger: ledger)
        let data = try encoder.encode(persisted)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureOrdinarySaveIsSafe() throws {
        switch FileQuarantine.state(for: fileURL) {
        case .unresolved:
            throw StoreRecoveryError.recoveryUnresolved
        case .invalid:
            throw StoreRecoveryError.recoveryRecordUnreadable
        case .resolved:
            try ensureExistingResolvedFileIsValid()
        case .absent:
            if FileQuarantine.legacyRecord(for: fileURL) != nil {
                throw StoreRecoveryError.recoveryUnresolved
            }
            // A marker-write failure leaves the unreadable original in place.
            // Validate before overwriting it, so that case cannot lose bytes.
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                _ = try readLedger()
            } catch {
                throw StoreRecoveryError.recoveryUnresolved
            }
        }
    }

    private func legacyOutcomeOrEmpty() -> LedgerLoadOutcome {
        guard let legacy = FileQuarantine.legacyRecord(for: fileURL) else { return .empty }
        do {
            let marker = try FileQuarantine.adoptLegacyRecovery(legacy, for: fileURL)
            return .unreadable(FileQuarantine.record(from: marker, for: fileURL))
        } catch {
            return .unreadable(legacy)
        }
    }

    private func quarantineFailure(reason: String) -> LedgerLoadOutcome {
        do {
            return .unreadable(try FileQuarantine.beginRecovery(for: fileURL, reason: reason))
        } catch {
            return .unreadable(QuarantineRecord(originalURL: fileURL, quarantinedURL: fileURL, reason: reason))
        }
    }

    private func unreadableSidecarRecord() -> QuarantineRecord {
        QuarantineRecord(
            originalURL: fileURL,
            quarantinedURL: fileURL,
            reason: "The recovery record cannot be read safely"
        )
    }

    private func ensureExistingResolvedFileIsValid() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            _ = try readLedger()
        } catch {
            throw StoreRecoveryError.recoveryUnresolved
        }
    }
}
