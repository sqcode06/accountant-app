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

    /// A file was there and could not be read. It has been moved aside.
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

        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            let bits = date.timeIntervalSince1970.bitPattern
            // Store as hex string (JSON-safe, exact, platform-independent)
            try c.encode(String(bits, radix: 16))
        }
        self.encoder = enc

        let dec = JSONDecoder()

        // Decode from either:
        // 1) New format: hex string bitPattern
        // 2) Double seconds (new format)
        // 2) ISO8601 string (old format, for backward compat)
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()

            // New format: hex string bitPattern
            if let s = try? c.decode(String.self),
            let bits = UInt64(s, radix: 16) {
                return Date(timeIntervalSince1970: Double(bitPattern: bits))
            }

            // Older format you used: JSON number
            if let t = try? c.decode(Double.self) {
                return Date(timeIntervalSince1970: t)
            }

            // Even older: ISO8601 string fallback
            let s = try c.decode(String.self)

            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoFrac.date(from: s) { return d }

            let isoNoFrac = ISO8601DateFormatter()
            isoNoFrac.formatOptions = [.withInternetDateTime]
            if let d = isoNoFrac.date(from: s) { return d }

            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date value: \(s)")
        }
        self.decoder = dec
    }

    public func load() throws -> Ledger {
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        do {
            return .loaded(try load())
        } catch {
            // Move it aside before returning. Quarantining here rather than in the
            // caller means the file is safe even if every layer above this one
            // mishandles the result.
            return .unreadable(
                FileQuarantine.move(fileURL, reason: String(describing: error))
            )
        }
    }

    public func save(_ ledger: Ledger) throws {
        let persisted = PersistedLedger(ledger: ledger)
        let data = try encoder.encode(persisted)

        // Ensure directory exists
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: fileURL, options: [.atomic])
    }
}
