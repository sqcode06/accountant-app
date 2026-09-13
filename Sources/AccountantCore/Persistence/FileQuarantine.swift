import Foundation

/// Where an unreadable file was put, and why.
public struct QuarantineRecord: Sendable, Equatable {
    public let originalURL: URL
    /// Where the protected bytes are expected to be. Equal to `originalURL` when
    /// the move has not completed, so callers must not overwrite the original.
    public let quarantinedURL: URL
    /// Human-readable description of the decode or read failure.
    public let reason: String

    public init(originalURL: URL, quarantinedURL: URL, reason: String) {
        self.originalURL = originalURL
        self.quarantinedURL = quarantinedURL
        self.reason = reason
    }

    /// Whether the protected copy is no longer at the original path.
    public var didMove: Bool { quarantinedURL != originalURL }
}

/// Errors returned while a damaged store is being explicitly recovered.
public enum StoreRecoveryError: Error, Equatable, Sendable {
    /// An ordinary save was attempted while a recovery record is still active.
    case recoveryUnresolved
    /// The durable recovery record cannot be read or updated safely.
    case recoveryRecordUnreadable
    /// There is no recovery operation to replace or complete.
    case noUnresolvedRecovery
    /// The old bytes have not been safely moved aside, so a replacement could
    /// overwrite the user's only copy.
    case originalNotSafelyQuarantined
    /// Recovery was completed before a replacement was written.
    case replacementMissing
    /// The replacement exists but cannot be decoded by this store.
    case replacementUnreadable
}

/// Durable state used only by the JSON stores in this module.
///
/// The sidecar is written *before* a broken file is moved. This ordering means a
/// termination between those operations remains fail-closed: on the next launch
/// the store reports `.unreadable`, never `.empty`.
enum FileRecoveryState {
    case absent
    case unresolved(RecoveryMarker)
    case resolved
    case invalid
}

struct RecoveryMarker: Codable, Sendable {
    var version: Int
    var state: String
    var relocation: String
    var originalFilename: String
    var quarantinedFilename: String
    var reason: String

    static let versionNumber = 2
    static let unresolved = "unresolved"
    static let resolved = "resolved"
    static let pending = "pending"
    static let moved = "moved"

    init(state: String, relocation: String, originalURL: URL, quarantinedURL: URL, reason: String) {
        self.version = Self.versionNumber
        self.state = state
        self.relocation = relocation
        self.originalFilename = originalURL.lastPathComponent
        self.quarantinedFilename = quarantinedURL.lastPathComponent
        self.reason = reason
    }

    func quarantinedURL(for originalURL: URL) -> URL {
        originalURL.deletingLastPathComponent().appendingPathComponent(quarantinedFilename)
    }
}

/// Moves files that could not be read out of harm's way, and persists a recovery
/// record for stores that need an explicit coordinated reset.
public enum FileQuarantine {
    /// Renames `url` aside and returns where it went.
    ///
    /// This compatibility helper intentionally has no sidecar. JSON stores use
    /// `beginRecovery` below so their recovery state survives a relaunch.
    public static func move(
        _ url: URL,
        reason: String,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> QuarantineRecord {
        let destination = availableDestination(for: url, now: now, fileManager: fileManager)
        do {
            try fileManager.moveItem(at: url, to: destination)
            return QuarantineRecord(originalURL: url, quarantinedURL: destination, reason: reason)
        } catch {
            return QuarantineRecord(originalURL: url, quarantinedURL: url, reason: reason)
        }
    }

    static func state(for url: URL, fileManager: FileManager = .default) -> FileRecoveryState {
        let sidecar = recoveryURL(for: url)
        guard fileManager.fileExists(atPath: sidecar.path) else { return .absent }

        do {
            let marker = try JSONDecoder().decode(RecoveryMarker.self, from: Data(contentsOf: sidecar))
            guard marker.version == RecoveryMarker.versionNumber,
                  marker.originalFilename == url.lastPathComponent,
                  isSafeFilename(marker.originalFilename),
                  isSafeFilename(marker.quarantinedFilename),
                  isExpectedQuarantineFilename(marker.quarantinedFilename, for: url),
                  marker.state == RecoveryMarker.unresolved || marker.state == RecoveryMarker.resolved,
                  marker.relocation == RecoveryMarker.pending || marker.relocation == RecoveryMarker.moved else {
                return .invalid
            }
            return marker.state == RecoveryMarker.unresolved ? .unresolved(marker) : .resolved
        } catch {
            return .invalid
        }
    }

    /// Finds an older quarantine created before durable sidecars existed.
    static func legacyRecord(for url: URL, fileManager: FileManager = .default) -> QuarantineRecord? {
        guard !fileManager.fileExists(atPath: url.path) else { return nil }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let prefix = "\(base).unreadable-"
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return nil }
        guard let name = names.filter({
            $0.hasPrefix(prefix) && (suffix.isEmpty || $0.hasSuffix(suffix))
        }).sorted().last else { return nil }
        return QuarantineRecord(
            originalURL: url,
            quarantinedURL: directory.appendingPathComponent(name),
            reason: "Recovered legacy unreadable-file quarantine"
        )
    }

    /// Writes the unresolved marker first, moves the file, then records that the
    /// move completed. If either write or the move fails, callers remain locked.
    static func beginRecovery(for url: URL, reason: String, fileManager: FileManager = .default) throws -> QuarantineRecord {
        let destination = availableDestination(for: url, now: Date(), fileManager: fileManager)
        var marker = RecoveryMarker(
            state: RecoveryMarker.unresolved,
            relocation: RecoveryMarker.pending,
            originalURL: url,
            quarantinedURL: destination,
            reason: reason
        )
        try write(marker, for: url)
        do {
            try fileManager.moveItem(at: url, to: destination)
            marker.relocation = RecoveryMarker.moved
            // A failure here is still safe. The pending marker plus the existing
            // destination is enough to keep the store locked and preserve bytes.
            try? write(marker, for: url)
        } catch {
            // The pending marker intentionally remains. Its original path still
            // owns the bytes, and replacement is refused until that changes.
        }
        return record(from: marker, for: url, fileManager: fileManager)
    }

    static func adoptLegacyRecovery(_ record: QuarantineRecord, for url: URL) throws -> RecoveryMarker {
        let marker = RecoveryMarker(
            state: RecoveryMarker.unresolved,
            relocation: RecoveryMarker.moved,
            originalURL: url,
            quarantinedURL: record.quarantinedURL,
            reason: record.reason
        )
        try write(marker, for: url)
        return marker
    }

    static func record(from marker: RecoveryMarker, for url: URL, fileManager: FileManager = .default) -> QuarantineRecord {
        let quarantinedURL = marker.quarantinedURL(for: url)
        let protectedURL = fileManager.fileExists(atPath: quarantinedURL.path) ? quarantinedURL : url
        return QuarantineRecord(originalURL: url, quarantinedURL: protectedURL, reason: marker.reason)
    }

    static func canReplace(_ marker: RecoveryMarker, for url: URL, fileManager: FileManager = .default) -> Bool {
        let quarantinedURL = marker.quarantinedURL(for: url)
        return quarantinedURL != url && fileManager.fileExists(atPath: quarantinedURL.path)
    }

    static func resolve(_ marker: RecoveryMarker, for url: URL) throws {
        var resolved = marker
        resolved.state = RecoveryMarker.resolved
        try write(resolved, for: url)
    }

    static func recoveryURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let name = ext.isEmpty ? "\(base).recovery" : "\(base).recovery.\(ext)"
        return directory.appendingPathComponent(name)
    }

    private static func write(_ marker: RecoveryMarker, for url: URL) throws {
        let data = try JSONEncoder().encode(marker)
        try data.write(to: recoveryURL(for: url), options: [.atomic])
    }

    private static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && URL(fileURLWithPath: name).lastPathComponent == name
    }

    private static func isExpectedQuarantineFilename(_ name: String, for url: URL) -> Bool {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let prefix = "\(base).unreadable-"
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return name.hasPrefix(prefix)
            && name.count > prefix.count + suffix.count
            && (suffix.isEmpty || name.hasSuffix(suffix))
    }

    /// `ledger.json` becomes `ledger.unreadable-20260811-172400.json`, with a
    /// counter appended if that name is taken.
    private static func availableDestination(for url: URL, now: Date, fileManager: FileManager) -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: now)

        func candidate(_ suffix: String) -> URL {
            let name = ext.isEmpty
                ? "\(base).unreadable-\(stamp)\(suffix)"
                : "\(base).unreadable-\(stamp)\(suffix).\(ext)"
            return directory.appendingPathComponent(name)
        }

        var destination = candidate("")
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = candidate("-\(counter)")
            counter += 1
        }
        return destination
    }
}
