import Foundation

/// Reads and writes one `Codable` value as a JSON file, distinguishing "nothing
/// here yet" from "something here I cannot read".
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    private let fileURL: URL
    private let fallback: @Sendable () -> Value
    private let encode: @Sendable (Value) throws -> Data
    private let decode: @Sendable (Data) throws -> Value
    private let writeData: @Sendable (Data, URL) throws -> Void

    /// - Parameter fallback: what `empty` means for this value — `Budget()`, `[]`.
    public init(fileURL: URL, fallback: @escaping @Sendable () -> Value) {
        self.init(fileURL: fileURL, fallback: fallback, encode: { value in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(value)
        }, decode: { try JSONDecoder().decode(Value.self, from: $0) })
    }

    /// Internal codec/write seam for versioned aggregate stores. All paths keep
    /// the same quarantine checks; tests can stop at the atomic commit boundary.
    init(
        fileURL: URL,
        fallback: @escaping @Sendable () -> Value,
        encode: @escaping @Sendable (Value) throws -> Data,
        decode: @escaping @Sendable (Data) throws -> Value,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        }
    ) {
        self.fileURL = fileURL
        self.fallback = fallback
        self.encode = encode
        self.decode = decode
        self.writeData = writeData
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

    public func loadOutcome() -> StoreLoadOutcome<Value> {
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
            return .loaded(try readValue())
        } catch {
            return quarantineFailure(reason: String(describing: error))
        }
    }

    /// Ordinary saves are deliberately blocked until an explicit recovery has
    /// replaced and completed every affected store.
    public func save(_ value: Value) throws {
        try ensureOrdinarySaveIsSafe()
        try write(value)
    }

    /// Writes a replacement while a recovery record remains unresolved. Calling
    /// `loadOutcome()` still reports `.unreadable` until `completeRecovery()`.
    /// On a healthy or first-run store this is equivalent to `save(_:)`.
    public func replaceForRecovery(_ value: Value) throws {
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
                    _ = try readValue()
                } catch {
                    throw StoreRecoveryError.originalNotSafelyQuarantined
                }
            }
        case .resolved:
            try ensureExistingResolvedFileIsValid()
        }
        try write(value)
    }

    /// Validates the replacement and durably resolves the recovery record. It is
    /// intentionally a no-op for healthy stores so a coordinator can call it for
    /// every store after all replacement writes succeed.
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
                _ = try readValue()
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

    /// The value to use when there is genuinely nothing stored yet.
    public func emptyValue() -> Value { fallback() }

    private func readValue() throws -> Value {
        let data = try Data(contentsOf: fileURL)
        return try decode(data)
    }

    private func write(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeData(encode(value), fileURL)
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
            // If the first marker write failed, the bad original remains at this
            // path. Decode it before overwriting so that failure stays fail-closed.
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                _ = try readValue()
            } catch {
                throw StoreRecoveryError.recoveryUnresolved
            }
        }
    }

    private func legacyOutcomeOrEmpty() -> StoreLoadOutcome<Value> {
        guard let legacy = FileQuarantine.legacyRecord(for: fileURL) else { return .empty }
        do {
            let marker = try FileQuarantine.adoptLegacyRecovery(legacy, for: fileURL)
            return .unreadable(FileQuarantine.record(from: marker, for: fileURL))
        } catch {
            return .unreadable(legacy)
        }
    }

    private func quarantineFailure(reason: String) -> StoreLoadOutcome<Value> {
        do {
            return .unreadable(try FileQuarantine.beginRecovery(for: fileURL, reason: reason))
        } catch {
            // The marker was not durable, so `beginRecovery` did not move the
            // original. Returning unreadable keeps callers from treating it empty.
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
            _ = try readValue()
        } catch {
            throw StoreRecoveryError.recoveryUnresolved
        }
    }
}
