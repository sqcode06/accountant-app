import Foundation

/// Reads a decimal written the way humans and banks actually write them.
///
/// There is no single convention. `1,234.56` and `1.234,56` are the same number
/// in different places, Swiss exports use `1'234.56`, and many use a plain or
/// non-breaking space for grouping. Accounting — including some bank exports —
/// writes negatives in parentheses, so `(42.50)` means −42.50.
///
/// Naive normalisation gets this wrong in a way that is easy to miss: replacing
/// every comma with a dot turns `1.234,56` into `1.234.56`, which fails to parse
/// at all. That failure is at least loud. The dangerous version is a string that
/// still parses into the wrong number.
public enum DecimalParsing {

    /// Parses `text`, or returns nil if it is not a number.
    public static func decimal(from text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        // Accounting negatives: (42.50) is -42.50.
        var isParenthesisedNegative = false
        if cleaned.hasPrefix("("), cleaned.hasSuffix(")") {
            isParenthesisedNegative = true
            cleaned = String(cleaned.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Grouping characters that are never decimal separators.
        for separator in [" ", "\u{00A0}", "\u{202F}", "'", "_"] {
            cleaned = cleaned.replacingOccurrences(of: separator, with: "")
        }

        // A trailing sign, as some exports write "42.50-".
        if cleaned.hasSuffix("-") {
            cleaned = "-" + cleaned.dropLast()
        }

        cleaned = normalizeSeparators(in: cleaned)

        // `Decimal(string:)` is far too forgiving to use as a validator. It reads
        // "EUR" as 0 — the leading E looks like exponent notation — and "--" as 0
        // as well. Either would put a silent zero into the ledger, so the shape is
        // checked here rather than trusted to the parse.
        guard isPlainNumber(cleaned),
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return nil
        }

        return isParenthesisedNegative ? -value : value
    }

    /// True only for `-?digits[.digits]` — no exponents, no stray symbols.
    private static func isPlainNumber(_ text: String) -> Bool {
        var hasDigit = false
        var hasPoint = false

        for (offset, character) in text.enumerated() {
            if character == "-" {
                guard offset == 0 else { return false }
            } else if character == "." {
                guard !hasPoint else { return false }
                hasPoint = true
            } else if character.isASCII, character.isNumber {
                hasDigit = true
            } else {
                return false
            }
        }

        return hasDigit
    }

    /// Resolves `.` and `,` into a single decimal point.
    ///
    /// The rule is positional rather than locale-based, because the text carries no
    /// locale: whichever separator appears **last** is the decimal one, and any
    /// earlier occurrences are grouping. That reads `1.234,56` and `1,234.56`
    /// correctly without being told which country produced them.
    private static func normalizeSeparators(in text: String) -> String {
        let lastDot = text.lastIndex(of: ".")
        let lastComma = text.lastIndex(of: ",")

        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            let decimalSeparator: Character = dot > comma ? "." : ","
            let grouping: Character = decimalSeparator == "." ? "," : "."

            return text
                .filter { $0 != grouping }
                .replacingOccurrences(of: String(decimalSeparator), with: ".")

        case (nil, .some):
            return resolveSingleSeparator(in: text, separator: ",")

        case (.some, nil):
            return resolveSingleSeparator(in: text, separator: ".")

        case (nil, nil):
            return text
        }
    }

    /// Decides whether the only separator present is grouping or a decimal point.
    ///
    /// Applied identically to `.` and `,`, because the ambiguity is identical:
    /// `1.234` and `1,234` are each either one-thousand-odd or one-point-something
    /// depending on where the file came from, and the text does not say.
    ///
    /// Two rules, both chosen for money specifically:
    /// - more than one occurrence is always grouping (`1.234.567`);
    /// - exactly three digits after a single separator is grouping, because the
    ///   currencies this app deals in have two decimal places, so three is far more
    ///   likely to be a thousands group than a fractional part.
    ///
    /// The second rule is wrong for three-decimal currencies such as KWD or BHD.
    /// None are offered, and getting `1,234` right is worth more than getting an
    /// unsupported currency's third decimal right.
    private static func resolveSingleSeparator(in text: String, separator: Character) -> String {
        if text.filter({ $0 == separator }).count > 1 {
            return text.replacingOccurrences(of: String(separator), with: "")
        }

        let parts = text.split(separator: separator, omittingEmptySubsequences: false)

        if parts.count == 2, parts[1].count == 3, parts[1].allSatisfy(\.isNumber) {
            return text.replacingOccurrences(of: String(separator), with: "")
        }

        return text.replacingOccurrences(of: String(separator), with: ".")
    }
}
