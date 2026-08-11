import Foundation

/// Where an unreadable file was put, and why.
public struct QuarantineRecord: Sendable, Equatable {
    public let originalURL: URL

    /// Where the file was moved to. Equal to `originalURL` when the move itself
    /// failed — the caller must still treat the data as protected in that case.
    public let quarantinedURL: URL

    /// Human-readable description of the decode or read failure.
    public let reason: String

    public init(originalURL: URL, quarantinedURL: URL, reason: String) {
        self.originalURL = originalURL
        self.quarantinedURL = quarantinedURL
        self.reason = reason
    }

    /// False when the file could not be moved aside. It is still on disk under its
    /// original name, so it must not be written over.
    public var didMove: Bool { quarantinedURL != originalURL }
}

/// Moves files that could not be read out of harm's way.
///
/// Exists because of a specific, fatal failure mode: a store that cannot decode its
/// file returns "empty", the app treats that as "no data yet", and the next save
/// writes an empty document over the real one. Renaming the file *before* anyone
/// can act on the failure makes the data recoverable no matter what the layers
/// above decide to do.
public enum FileQuarantine {

    /// Renames `url` aside and returns where it went.
    ///
    /// Never throws. A failure to move is reported through `didMove` rather than as
    /// an error, because the caller's response is the same either way — refuse to
    /// write — and an error here would tempt callers into a `try?` that discards
    /// exactly the information they need.
    public static func move(
        _ url: URL,
        reason: String,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> QuarantineRecord {
        let destination = availableDestination(for: url, now: now, fileManager: fileManager)

        do {
            try fileManager.moveItem(at: url, to: destination)

            return QuarantineRecord(
                originalURL: url,
                quarantinedURL: destination,
                reason: reason
            )
        } catch {
            return QuarantineRecord(
                originalURL: url,
                quarantinedURL: url,
                reason: reason
            )
        }
    }

    /// `ledger.json` becomes `ledger.unreadable-20260811-172400.json`, with a
    /// counter appended if that name is taken.
    ///
    /// Seconds resolution would collide if a file is quarantined twice within the
    /// same second — which happens the moment anything retries in a loop — so the
    /// counter is not decoration.
    private static func availableDestination(
        for url: URL,
        now: Date,
        fileManager: FileManager
    ) -> URL {
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
