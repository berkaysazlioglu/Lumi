import Foundation

/// En az bir ayırıcı (`/` ya da `\`) taşıyan yollar — Orca `terminal-links`
/// (VSCode `terminalLocalLinkDetector` port'u) paritesi.
///
/// İki geçiş vardır: önce **boşluklu** yollar (`/Users/A/Foo Bar/file.ts` tek
/// link olsun, `Foo` ile `Bar/file.ts`'ye bölünmesin), sonra **düz** yollar.
/// Düz desen `( ) [ ]`'yi de yol karakteri sayar — framework route dosyaları
/// (`app/(shop)/products/[id]/page.tsx`) bütün kalır. Uzantısız yollar
/// (`src/foo`, `./bin`) da adaydır; gerçek bir link olup olmadıklarına diskin
/// cevabı karar verir.
enum TerminalPathLinkScanner {
    private static let pathStart = #"(?:~[\\/]|[\\/]|\.{1,2}[\\/]|[A-Za-z]:[\\/]|[A-Za-z0-9._-]+[\\/])"#
    private static let lineSuffix = #"(?::\d+)?(?::\d+)?"#
    private static let localPath = TerminalLinkText.regex(
        pathStart + #"[A-Za-z0-9._~\-/%+@\\()\[\]]*"# + lineSuffix
    )
    /// Kasıtlı olarak geniş: "boşluktan sonra ayırıcı" doğrulaması regex içinde
    /// yapılsaydı uzun TUI satırlarında geri izleme patlardı. Süzme kodda yapılır.
    private static let spacedPath = TerminalLinkText.regex(
        pathStart + #"[^()\[\]{}'",;<>|`\r\n]+"# + lineSuffix
    )
    private static let extensionSuffix = TerminalLinkText.regex(#"\.[A-Za-z0-9_+-]+(?::\d+)?(?::\d+)?(?=\s+|$)"#)
    private static let endsWithExtension = TerminalLinkText.regex(#"\.[A-Za-z0-9_+-]+(?::\d+)?(?::\d+)?$"#)
    private static let pathStartAfterSpace = TerminalLinkText.regex(#"(?:^|\s)(?:~[\\/]|[\\/]|\.{1,2}[\\/]|[A-Za-z]:[\\/])"#)
    private static let whitespaceRun = TerminalLinkText.regex(#"\s+"#)
    private static let uriSchemeTail = TerminalLinkText.regex(#"[A-Za-z][A-Za-z0-9+.-]*:(?://)?$"#)
    private static let uriPrefixCharacters: Set<unichar> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+./:-".utf16
    )

    private enum SpacedFilter: CaseIterable {
        /// Boşluktan SONRA bir ayırıcı daha var: `Foo Bar/file.ts`.
        case separatorAfterWhitespace
        /// Boşluklu ve bir uzantıyla bitiyor: `My File.txt`.
        case extensionTerminated
        /// Satırın sonuna dayanıyor: `~/Library/Application Support`.
        case lineEnding
    }

    /// Satırdaki yol adayları: önce boşluklular (uzun önce), sonra düzler.
    /// Düz bir eşleşme boşluklu bir adayla çakışsa da LİSTEDE KALIR — Orca onu
    /// atar; Lumi'de seçim "diskte var olan en uzun aday" olduğu için boşluklu
    /// aday diskte yoksa düz yol (`src/foo is great` → `src/foo`) yine link olur.
    static func links(in line: NSString) -> [TerminalLinkTextRange] {
        guard line.range(of: "/").location != NSNotFound || line.range(of: "\\").location != NSNotFound else {
            return []
        }
        var links = spacedLinks(in: line)
        for range in TerminalLinkText.matches(localPath, in: line).compactMap(TerminalLinkText.trimBoundaryPunctuation) {
            guard !isInsideURIScheme(range, in: line), containsSeparator(range.text) else { continue }
            guard TerminalLinkText.isLinkableFileTarget(range.text), !links.contains(range) else { continue }
            links.append(range)
        }
        return links
    }

    private static func spacedLinks(in line: NSString) -> [TerminalLinkTextRange] {
        let candidates = TerminalLinkText.matches(spacedPath, in: line).compactMap(TerminalLinkText.trimBoundaryPunctuation)
        var links: [TerminalLinkTextRange] = []
        var claimed: [TerminalLinkTextRange] = []
        for filter in SpacedFilter.allCases {
            for range in candidates where passes(range, filter: filter, in: line) {
                guard !claimed.contains(where: range.overlaps), !isInsideURIScheme(range, in: line) else { continue }
                // Satır sonuna dayanan boşluklu yolda kelime kelime kısalan önekler
                // de aday olur: hangisinin diskte olduğunu bilmiyoruz.
                let variants = filter == .lineEnding ? [range] + lineEndingPrefixes(of: range) : [range]
                let parsed = variants
                    .map { trimTrailingProse(TerminalLinkText.trimTrailingWhitespace($0)) }
                    .filter { TerminalLinkText.isLinkableFileTarget($0.text) }
                guard let first = parsed.first else { continue }
                // Önekler düzyazı kırpmasıyla aynı aralığa inebilir.
                for variant in parsed where !links.contains(variant) { links.append(variant) }
                claimed.append(first)
            }
        }
        return links
    }

    private static func passes(_ range: TerminalLinkTextRange, filter: SpacedFilter, in line: NSString) -> Bool {
        switch filter {
        case .separatorAfterWhitespace:
            return hasSeparatorAfterWhitespace(range.text)
        case .extensionTerminated:
            let trimmed = TerminalLinkText.trimTrailingWhitespace(trimTrailingProse(range)).text
            return containsWhitespace(trimmed) && TerminalLinkText.isMatch(endsWithExtension, trimmed)
        case .lineEnding:
            let trimmed = TerminalLinkText.trimTrailingWhitespace(range).text
            let rest = line.substring(from: range.end)
            return containsWhitespace(trimmed) && rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Uzantıyla biten TEK bir yolu tutar; arkasındaki düzyazıyı ya da ikinci,
    /// ilgisiz bir yolu atar. Satır sonundaki uzantılı parça yalnız yol gibiyse
    /// (ayırıcı içeriyorsa) aralığı uzatır: `v1.2 reports/result.json` uzar,
    /// `failed to start app.py` uzamaz.
    private static func trimTrailingProse(_ range: TerminalLinkTextRange) -> TerminalLinkTextRange {
        let text = range.text as NSString
        var selectedLength: Int?
        for match in TerminalLinkText.matches(extensionSuffix, in: text) {
            let prefix = text.substring(to: match.end)
            guard pathStartCount(prefix) <= 1 else { continue }
            let addsSeparator = selectedLength.map {
                containsSeparator(text.substring(with: NSRange(location: $0, length: match.end - $0)))
            } ?? false
            if match.end < text.length || selectedLength == nil || addsSeparator {
                selectedLength = match.end
            }
        }
        guard let selectedLength else { return range }
        return TerminalLinkTextRange(
            start: range.start,
            end: range.start + selectedLength,
            text: text.substring(to: selectedLength)
        )
    }

    private static func lineEndingPrefixes(of range: TerminalLinkTextRange) -> [TerminalLinkTextRange] {
        let text = range.text as NSString
        let prefixes = TerminalLinkText.matches(whitespaceRun, in: text).compactMap { gap -> TerminalLinkTextRange? in
            let prefix = TerminalLinkText.trimTrailingWhitespace(
                TerminalLinkTextRange(start: range.start, end: range.start + gap.start, text: text.substring(to: gap.start))
            )
            return prefix.text.contains(" ") ? prefix : nil
        }
        return prefixes.reversed()
    }

    /// Yerel yol deseni bir URL'nin `//host/path` kısmından başlayabilir.
    private static func isInsideURIScheme(_ range: TerminalLinkTextRange, in line: NSString) -> Bool {
        if range.text.contains("://") { return true }
        var start = range.start
        while start > 0, uriPrefixCharacters.contains(line.character(at: start - 1)) { start -= 1 }
        let prefix = line.substring(with: NSRange(location: start, length: range.start - start))
        guard TerminalLinkText.isMatch(uriSchemeTail, prefix) else { return false }
        return prefix.hasSuffix("://") || range.text.hasPrefix("//")
    }

    private static func pathStartCount(_ text: String) -> Int {
        pathStartAfterSpace.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func hasSeparatorAfterWhitespace(_ text: String) -> Bool {
        var sawWhitespace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                sawWhitespace = true
            } else if sawWhitespace, scalar == "/" || scalar == "\\" {
                return true
            }
        }
        return false
    }

    private static func containsWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func containsSeparator(_ text: String) -> Bool {
        text.contains("/") || text.contains("\\")
    }
}
