import Foundation

/// Terminal satırında bulunan bir link adayı.
public struct DetectedTerminalLink: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// http/https — diske sorulmaz.
        case url
        /// `file://` URI'si.
        case fileURI
        /// En az bir ayırıcı taşıyan yol (`src/a.ts`, `./bin`, `~/x`, `/abs`).
        case path
        /// Ayırıcısız dosya adı (`README.md`, `Makefile`).
        case bareFilename
    }

    public let kind: Kind
    /// `TerminalLinkResolver`'a giden metin (uçları kırpılmış; `:satır:sütun`
    /// eki dahil — çözümleyici onu ayıklar).
    public let text: String
    /// Satır metninde UTF-16 ofsetleri.
    public let range: Range<Int>

    public init(kind: Kind, text: String, range: Range<Int>) {
        self.kind = kind
        self.text = text
        self.range = range
    }

    /// Yol türündeki adaylar ancak diskte varsa link olur (Orca paritesi:
    /// olmayan yolun altı çizilmez, tıkı popover açmaz).
    public var requiresExistence: Bool { kind != .url }
}

/// Terminal satırındaki link adaylarının tek kaynağı (Orca `terminal-links` +
/// `terminal-http-url-extraction` port'u; kod kopyalanmadı, kurallar taşındı).
///
/// Saftır: diske hiç dokunmaz. Yol adaylarından hangisinin gerçek link olduğuna
/// çağıran katman diskin cevabıyla karar verir — `candidates(in:at:)` sırası
/// "önce bunu dene" sırasıdır.
public enum TerminalLinkDetector {
    /// Bundan uzun mantıksal satırlar taranmaz (hover etkileşimli kalsın).
    public static let maxLineLength = 16_384

    /// Satırdaki tüm adaylar: URL'ler, ardından dosya adayları (`file://`,
    /// ayırıcılı yollar, çıplak dosya adları). URL'yle çakışan dosya adayı düşer.
    public static func links(in line: String) -> [DetectedTerminalLink] {
        let text = line as NSString
        guard text.length > 0, text.length <= maxLineLength else { return [] }
        let urls = TerminalHTTPURLScanner.links(in: text)
        let uris = TerminalFileURIScanner.links(in: text).filter { !overlapsAny($0, urls) }
        let paths = TerminalPathLinkScanner.links(in: text)
            .filter { !overlapsAny($0, urls) && !overlapsAny($0, uris) }
        let bare = TerminalBareFilenameScanner.links(in: text, excluding: urls + uris + paths)
        return urls.map { make(.url, $0) } + uris.map { make(.fileURI, $0) }
            + paths.map { make(.path, $0) } + bare.map { make(.bareFilename, $0) }
    }

    /// `offset`'teki (UTF-16) karakteri kapsayan adaylar, denenme sırasıyla:
    /// bir URL kapsıyorsa yalnız o; değilse dosya adayları uzundan kısaya
    /// (eşit uzunlukta algılama sırası korunur).
    public static func candidates(in line: String, at offset: Int) -> [DetectedTerminalLink] {
        let covering = links(in: line).filter { $0.range.contains(offset) }
        if let url = covering.first(where: { $0.kind == .url }) { return [url] }
        // Boşluklu ve düz geçiş aynı aralığı üretebilir; ilk geleni kalır.
        var seen = Set<Range<Int>>()
        let unique = covering.filter { seen.insert($0.range).inserted }
        return unique.enumerated()
            .sorted { lhs, rhs in
                lhs.element.range.count != rhs.element.range.count
                    ? lhs.element.range.count > rhs.element.range.count
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func make(_ kind: DetectedTerminalLink.Kind, _ range: TerminalLinkTextRange) -> DetectedTerminalLink {
        DetectedTerminalLink(kind: kind, text: range.text, range: range.start ..< range.end)
    }

    private static func overlapsAny(_ range: TerminalLinkTextRange, _ others: [TerminalLinkTextRange]) -> Bool {
        others.contains(where: range.overlaps)
    }
}
