import Foundation

/// Reads a statement file off disk as text.
///
/// Two things make this less trivial than it looks.
///
/// Encoding: Baltic bank exports are not reliably UTF-8. A file written in
/// Windows-1257 decoded as UTF-8 either fails outright or turns every õ, ä and ü
/// into replacement characters, which then land in memos forever. So decoding
/// walks a list of candidates and takes the first that produces sane text.
///
/// Access: files chosen through the document picker live outside the app's
/// sandbox and need their security scope opened first, and closed after.
enum StatementFile {

    enum ReadError: LocalizedError {
        case permissionDenied
        case unreadableEncoding

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "The file could not be opened. Try choosing it again."
            case .unreadableEncoding:
                "The file is not readable as text. Export it as CSV rather than a spreadsheet."
            }
        }
    }

    /// Candidate encodings, most likely first.
    ///
    /// `windowsCP1254` is Apple's constant for the Baltic/Turkish family available
    /// on iOS; `isoLatin2` covers central European exports. UTF-8 first because
    /// modern exports are, and a wrong guess there fails cleanly rather than
    /// producing plausible nonsense.
    private static let encodings: [String.Encoding] = [
        .utf8,
        .windowsCP1252,
        .isoLatin2,
        .isoLatin1,
        .macOSRoman
    ]

    static func readText(at url: URL) throws -> String {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw ReadError.permissionDenied
        }

        for encoding in encodings {
            guard var text = String(data: data, encoding: encoding) else { continue }

            // A decode that "succeeds" but is riddled with replacement characters
            // is worse than one that fails, because the damage is silent.
            guard !text.contains("\u{FFFD}") else { continue }

            // Strip a byte-order mark; it would otherwise become part of the first
            // header name and stop that column being found.
            if text.hasPrefix("\u{FEFF}") {
                text.removeFirst()
            }

            return text
        }

        throw ReadError.unreadableEncoding
    }
}
