import Foundation

/// Satırdaki http/https adresleri (Orca `terminal-http-url-extraction` paritesi).
///
/// Regex değil, doğrusal bir tarayıcıdır: şema öneki `indexOf` ile bulunur,
/// gövde ilk sonlandırıcıda biter, sondaki noktalama kırpılır. Önekten önce bir
/// ASCII kelime karakteri varsa (`xhttps://`) eşleşme sayılmaz.
enum TerminalHTTPURLScanner {
    /// Hover'da koşar; dev bir token ana thread'i bağlamasın.
    static let maxLength = 2048

    private static let prefixes = ["https://", "http://"]
    /// Gövdeyi bitiren ASCII karakterler (boşluk ayrıca).
    private static let bodyTerminators: Set<unichar> = Set("\"'!*(){}|\\^<>`".utf16)
    /// Sondan kırpılan ASCII noktalama (boşluk ayrıca).
    private static let trailingPunctuation: Set<unichar> = Set("\"':,.!?{}|\\^~[]()<>`".utf16)

    static func links(in line: NSString) -> [TerminalLinkTextRange] {
        var links: [TerminalLinkTextRange] = []
        var searchStart = 0
        while searchStart < line.length, let start = nextScheme(in: line, from: searchStart) {
            guard hasWordBoundary(line, before: start) else {
                searchStart = start + 1
                continue
            }
            let rawEnd = candidateEnd(in: line, from: start)
            let end = trimmedEnd(in: line, start: start, rawEnd: rawEnd)
            searchStart = max(rawEnd, start + 1)
            guard end > start, rawEnd - start <= maxLength else { continue }
            let text = line.substring(with: NSRange(location: start, length: end - start))
            guard let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            links.append(TerminalLinkTextRange(start: start, end: end, text: text))
        }
        return links
    }

    private static func nextScheme(in line: NSString, from start: Int) -> Int? {
        let searchRange = NSRange(location: start, length: line.length - start)
        return prefixes
            .map { line.range(of: $0, options: .caseInsensitive, range: searchRange).location }
            .filter { $0 != NSNotFound }
            .min()
    }

    private static func hasWordBoundary(_ line: NSString, before index: Int) -> Bool {
        index == 0 || !isASCIIWord(line.character(at: index - 1))
    }

    private static func candidateEnd(in line: NSString, from start: Int) -> Int {
        let scanEnd = min(line.length, start + maxLength + 1)
        for index in start ..< scanEnd where isBodyTerminator(line.character(at: index)) {
            return index
        }
        return scanEnd
    }

    private static func trimmedEnd(in line: NSString, start: Int, rawEnd: Int) -> Int {
        var end = rawEnd
        while end > start, isTrailingPunctuation(line.character(at: end - 1)) { end -= 1 }
        return end
    }

    private static func isBodyTerminator(_ unit: unichar) -> Bool {
        if TerminalLinkText.isWhitespace(unit) || bodyTerminators.contains(unit) { return true }
        // ASCII dışında yalnız noktalama/simge/boşluk biter: URL yolu kodlanmamış
        // CJK taşıyabilir, tam genişlikli parantez ve ideografik boşluk ise bitirir.
        guard unit > 0x7E, let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar)
            || CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isTrailingPunctuation(_ unit: unichar) -> Bool {
        TerminalLinkText.isWhitespace(unit) || trailingPunctuation.contains(unit)
    }

    private static func isASCIIWord(_ unit: unichar) -> Bool {
        (0x30 ... 0x39).contains(unit) || (0x41 ... 0x5A).contains(unit)
            || unit == 0x5F || (0x61 ... 0x7A).contains(unit)
    }
}
