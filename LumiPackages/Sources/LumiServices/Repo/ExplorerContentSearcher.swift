import Foundation
import LumiKit

/// Repo dosyalarında metin/regex araması (Explorer > Contents).
///
/// Sınırlar: dosya başına 2 MB, toplam 32 MB okuma bütçesi, 10.000 yol, 500
/// eşleşme — aşılınca `isLimited` işaretlenir. Binary (NUL içeren) ve
/// UTF-8 olmayan dosyalar atlanır. Regex tüm dosya metninde koşar; satır
/// numarası eşleşme konumundan türetilir (satır satır regex çok daha yavaştı).
struct ExplorerContentSearcher {
    static let maxFileBytes = 2 * 1024 * 1024
    static let totalByteBudget = 32 * 1024 * 1024
    static let maxPaths = 10_000
    static let maxMatches = 500
    static let maxLineLength = 500

    static func search(repoPath: String, paths: [String], query: ExplorerContentQuery) async throws -> ExplorerContentResult {
        guard !query.isEmpty else { return ExplorerContentResult() }
        let regex = try query.regularExpression()
        var matches: [ExplorerContentMatch] = []
        var remainingBytes = totalByteBudget
        var limited = paths.count > maxPaths
        let guardPath = RepoPathGuard()
        for path in paths.prefix(maxPaths) where query.includes(path: path) {
            try Task.checkCancellation()
            guard let text = readText(repoPath: repoPath, path: path, guardPath: guardPath, budget: &remainingBytes, limited: &limited)
            else { continue }
            let found = collect(in: text, path: path, regex: regex, room: maxMatches - matches.count)
            matches.append(contentsOf: found)
            if matches.count >= maxMatches { return ExplorerContentResult(matches: matches, isLimited: true) }
            if remainingBytes == 0 { limited = true; break }
        }
        return ExplorerContentResult(matches: matches, isLimited: limited)
    }

    /// Dosyayı bütçe içinde UTF-8 metin olarak okur; okunamaz/binary/büyükse nil.
    private static func readText(
        repoPath: String, path: String, guardPath: RepoPathGuard,
        budget: inout Int, limited: inout Bool
    ) -> String? {
        guard let resolved = try? guardPath.resolve(repoPath: repoPath, relativePath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: resolved)) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        guard size <= UInt64(maxFileBytes) else { limited = true; return nil }
        guard let data = try? handle.read(upToCount: min(maxFileBytes, budget)) else { return nil }
        budget -= data.count
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Tüm metindeki eşleşmeleri satır/kolon bilgisiyle toplar.
    private static func collect(in text: String, path: String, regex: NSRegularExpression, room: Int) -> [ExplorerContentMatch] {
        guard room > 0 else { return [] }
        let nsText = text as NSString
        let hits = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var result: [ExplorerContentMatch] = []
        var lineNumber = 1
        var lineStart = 0
        var scanned = 0
        for hit in hits where hit.range.length > 0 {
            // Satır sayacı ileri sarılır: eşleşmeler artan sırada gelir.
            while scanned < hit.range.location {
                if nsText.character(at: scanned) == 10 { lineNumber += 1; lineStart = scanned + 1 }
                scanned += 1
            }
            let lineEnd = lineEndIndex(nsText, from: hit.range.location)
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let line = nsText.substring(with: lineRange)
            let column = hit.range.location - lineStart
            guard column < maxLineLength else { continue }
            result.append(ExplorerContentMatch(
                path: path, line: lineNumber,
                text: String(line.prefix(maxLineLength)),
                column: (line as NSString).substring(to: column).count,
                length: (nsText.substring(with: hit.range) as String).count
            ))
            if result.count == room { break }
        }
        return result
    }

    private static func lineEndIndex(_ text: NSString, from location: Int) -> Int {
        var index = location
        while index < text.length, text.character(at: index) != 10 { index += 1 }
        return index
    }
}
