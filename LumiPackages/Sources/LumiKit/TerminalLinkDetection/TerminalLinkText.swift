import Foundation

/// Satır metninde UTF-16 ofsetleriyle bir aralık ve o aralığın metni.
/// Algılayıcının tüm geçişleri `NSString` (UTF-16) üzerinde çalışır; terminal
/// tarafı hücre ↔ ofset eşlemesini aynı birimle kurar.
struct TerminalLinkTextRange: Equatable {
    var start: Int
    var end: Int
    var text: String

    var length: Int { end - start }

    func overlaps(_ other: TerminalLinkTextRange) -> Bool {
        start < other.end && other.start < end
    }
}

/// Algılama geçişlerinin ortak yardımcıları (Orca `terminal-file-link-detection-ranges`
/// + `explicit-file-link-target` + `file-link-location` karşılıkları).
enum TerminalLinkText {
    /// Eşleşmenin başına/sonuna yapışan cümle noktalaması — `(src/a.ts)`,
    /// `"README.md",` gibi. Kök içi `()`/`[]` segmentleri (`app/(shop)/[id]`)
    /// yalnız uçta değilse korunur.
    private static let leadingTrim: Set<unichar> = Set("([{\"'".utf16)
    private static let trailingTrim: Set<unichar> = Set(")]}\"',;.".utf16)

    private static let location = regex(#"^(.*?)(?::(\d+))?(?::(\d+))?$"#)
    private static let separatorThenSpace = regex(#"^[\\/]\s"#)
    private static let bareRoot = regex(#"^(?:[\\/]+|~[\\/]|[A-Za-z]:[\\/])$"#)
    private static let anchoredRoot = regex(#"^(?:~[\\/]|[\\/]|[A-Za-z]:[\\/])"#)

    /// Sabit desenler derleme zamanında bilinir; geçersiz desen programcı hatasıdır.
    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Geçersiz terminal link deseni: \(pattern) — \(error)")
        }
    }

    static func matches(_ regex: NSRegularExpression, in line: NSString) -> [TerminalLinkTextRange] {
        regex.matches(in: line as String, range: NSRange(location: 0, length: line.length)).map {
            TerminalLinkTextRange(
                start: $0.range.location,
                end: $0.range.location + $0.range.length,
                text: line.substring(with: $0.range)
            )
        }
    }

    static func isMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Uçlardaki noktalamayı kırpar; geriye bir şey kalmazsa `nil`.
    static func trimBoundaryPunctuation(_ range: TerminalLinkTextRange) -> TerminalLinkTextRange? {
        let text = range.text as NSString
        var start = 0
        var end = text.length
        while start < end, leadingTrim.contains(text.character(at: start)) { start += 1 }
        while end > start, trailingTrim.contains(text.character(at: end - 1)) { end -= 1 }
        guard start < end else { return nil }
        return TerminalLinkTextRange(
            start: range.start + start,
            end: range.start + end,
            text: text.substring(with: NSRange(location: start, length: end - start))
        )
    }

    /// Sondaki boşlukları atar (JS `trimEnd`).
    static func trimTrailingWhitespace(_ range: TerminalLinkTextRange) -> TerminalLinkTextRange {
        let text = range.text as NSString
        var end = text.length
        while end > 0, isWhitespace(text.character(at: end - 1)) { end -= 1 }
        return TerminalLinkTextRange(
            start: range.start,
            end: range.start + end,
            text: text.substring(to: end)
        )
    }

    static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// `yol[:satır[:sütun]]` ayrıştırması; 1'den küçük satır/sütun linki geçersiz kılar.
    static func parseLocation(_ value: String) -> (path: String, line: Int?, column: Int?)? {
        let text = value as NSString
        guard let match = location.firstMatch(in: value, range: NSRange(location: 0, length: text.length)),
              match.range(at: 1).length > 0 else { return nil }
        let path = text.substring(with: match.range(at: 1))
        let line = number(at: match.range(at: 2), in: text)
        let column = number(at: match.range(at: 3), in: text)
        if let line, line < 1 { return nil }
        if let column, column < 1 { return nil }
        return (path, line, column)
    }

    /// Link olabilecek bir dosya hedefi mi (Orca `parseExplicitFileLinkTarget`):
    /// `/ foo` gibi ayırıcı+boşluk başlangıcı ve sonu ayırıcıyla biten göreli ya
    /// da çıplak kök yollar (`/`, `~/`) link değildir; satır ekli dizin de değildir.
    static func isLinkableFileTarget(_ value: String) -> Bool {
        guard let parsed = parseLocation(value) else { return false }
        if isMatch(separatorThenSpace, parsed.path) { return false }
        guard parsed.path.hasSuffix("/") || parsed.path.hasSuffix("\\") else { return true }
        if parsed.line != nil || parsed.column != nil { return false }
        return !isMatch(bareRoot, parsed.path) && isMatch(anchoredRoot, parsed.path)
    }

    private static func number(at range: NSRange, in text: NSString) -> Int? {
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return Int(text.substring(with: range))
    }
}
