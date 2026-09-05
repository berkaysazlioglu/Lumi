public struct ExplorerContentMatch: Sendable, Equatable, Identifiable {
    public var id: String { "\(path):\(line)" }
    public let path: String
    public let line: Int
    public let text: String

    public init(path: String, line: Int, text: String) {
        self.path = path
        self.line = line
        self.text = text
    }
}

public struct ExplorerContentResult: Sendable, Equatable {
    public let matches: [ExplorerContentMatch]
    public let isLimited: Bool

    public init(matches: [ExplorerContentMatch] = [], isLimited: Bool = false) {
        self.matches = matches
        self.isLimited = isLimited
    }
}

/// Tek dosyanın eşleşmeleri — içerik arama sonuç listesinin katlanabilir birimi.
public struct ExplorerContentFileGroup: Sendable, Equatable, Identifiable {
    public var id: String { path }
    /// Repo köküne göre relative path.
    public let path: String
    public let matches: [ExplorerContentMatch]

    public init(path: String, matches: [ExplorerContentMatch]) {
        self.path = path
        self.matches = matches
    }

    /// Dosya adı (başlık satırının birincil metni).
    public var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Üst dizin; kök seviyesindeki dosyada boş.
    public var directory: String {
        let parts = path.split(separator: "/").dropLast()
        return parts.joined(separator: "/")
    }
}

public extension ExplorerContentResult {
    /// Eşleşmeleri dosya bazında gruplar; dosya sırası ilk görülme sırasıdır
    /// (arayıcı zaten dosya dosya ilerlediği için bu doğal sıra korunur).
    var fileGroups: [ExplorerContentFileGroup] {
        var order: [String] = []
        var byPath: [String: [ExplorerContentMatch]] = [:]
        for match in matches {
            if byPath[match.path] == nil { order.append(match.path) }
            byPath[match.path, default: []].append(match)
        }
        return order.map { ExplorerContentFileGroup(path: $0, matches: byPath[$0] ?? []) }
    }

    /// Kaç eşleşme kaç dosyada — sonuç listesinin özet satırı.
    var fileCount: Int { Set(matches.map(\.path)).count }
}

/// Eşleşme satırının vurgulama için üçe bölünmüş hâli.
///
/// Dar kenar çubuğunda uzun bir ön ek vurguyu sağa itip görünmez kılıyordu;
/// VS Code'un arama görünümü gibi ön ek soldan kırpılır (`lcut`).
public struct ExplorerMatchPreview: Sendable, Equatable {
    /// Eşleşmeden önceki (gerekirse soldan kırpılmış) metin.
    public let before: String
    /// Eşleşen metnin ORİJİNAL yazımı (arama büyük/küçük harf duyarsızdır).
    public let match: String
    /// Eşleşmeden sonraki metin.
    public let after: String

    /// Ön ekte tutulan en fazla karakter; aşılırsa baştan "…" ile kırpılır.
    public static let prefixLimit = 26

    public init(before: String, match: String, after: String) {
        self.before = before
        self.match = match
        self.after = after
    }

    /// Satırı sorguya göre böler. Sorgu bulunamazsa satırın tamamı `before` olur.
    public static func make(text: String, query: String) -> ExplorerMatchPreview {
        guard !query.isEmpty,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return ExplorerMatchPreview(before: text, match: "", after: "")
        }
        let rawPrefix = String(text[text.startIndex..<range.lowerBound])
            .drop { $0 == " " || $0 == "\t" }
        let prefix = rawPrefix.count > prefixLimit
            ? "…" + String(rawPrefix.suffix(prefixLimit))
            : String(rawPrefix)
        return ExplorerMatchPreview(
            before: prefix,
            match: String(text[range]),
            after: String(text[range.upperBound...])
        )
    }
}
