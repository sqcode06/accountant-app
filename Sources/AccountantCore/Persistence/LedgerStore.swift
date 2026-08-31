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
        LedgerDateCoding.apply(to: enc)
        self.encoder = enc

        let dec = JSONDecoder()
        LedgerDateCoding.apply(to: dec)
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
