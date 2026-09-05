import Foundation

/// İçerik aramasının tam sorgusu: metin + eşleme seçenekleri + dosya filtreleri
/// (Orca / VS Code arama görünümü: `Aa`, `ab`, `.*`, include/exclude).
///
/// Değer tipidir; seçenek değişimi yeni bir sorgu üretir ve `task(id:)` bunu
/// yeni arama olarak görür.
public struct ExplorerContentQuery: Sendable, Equatable {
    public var text: String
    /// `Aa` — büyük/küçük harf ayrımı.
    public var isCaseSensitive: Bool
    /// `ab` — yalnız tam kelime eşleşmeleri.
    public var isWholeWord: Bool
    /// `.*` — metin bir düzenli ifade olarak yorumlanır.
    public var isRegex: Bool
    /// Virgülle ayrılmış glob'lar (`*.swift, Sources/**`); boşsa hepsi dahil.
    public var includePatterns: String
    /// Virgülle ayrılmış glob'lar (`*.min.js, dist/**`); boşsa hiçbiri hariç.
    public var excludePatterns: String

    public init(
        text: String,
        isCaseSensitive: Bool = false,
        isWholeWord: Bool = false,
        isRegex: Bool = false,
        includePatterns: String = "",
        excludePatterns: String = ""
    ) {
        self.text = text
        self.isCaseSensitive = isCaseSensitive
        self.isWholeWord = isWholeWord
        self.isRegex = isRegex
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
    }

    public enum QueryError: Error, LocalizedError, Equatable, Sendable {
        case invalidRegex(String)

        public var errorDescription: String? {
            switch self {
            case .invalidRegex(let pattern): return "Invalid regular expression: \(pattern)"
            }
        }
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isEmpty: Bool { trimmedText.isEmpty }

    /// Aynı seçeneklerle farklı metin.
    public func with(text: String) -> ExplorerContentQuery {
        var copy = self
        copy.text = text
        return copy
    }

    /// Seçeneklerden tek bir regex deseni türetir: düz metin kaçışlanır, tam
    /// kelime `\b` ile sarılır. Geçersiz regex `QueryError.invalidRegex` fırlatır.
    public func regularExpression() throws -> NSRegularExpression {
        var pattern = isRegex ? trimmedText : NSRegularExpression.escapedPattern(for: trimmedText)
        if isWholeWord { pattern = "\\b(?:\(pattern))\\b" }
        // Arama satır tabanlıdır: `^`/`$` her satırın başı/sonu demektir.
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !isCaseSensitive { options.insert(.caseInsensitive) }
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw QueryError.invalidRegex(trimmedText)
        }
    }

    /// Dosya filtreleri: include boşsa her yol geçer; exclude eşleşen düşer.
    public func includes(path: String) -> Bool {
        let include = ExplorerGlob.patterns(includePatterns)
        let exclude = ExplorerGlob.patterns(excludePatterns)
        if !include.isEmpty, !include.contains(where: { ExplorerGlob.matches($0, path: path) }) { return false }
        if exclude.contains(where: { ExplorerGlob.matches($0, path: path) }) { return false }
        return true
    }
}

/// Basit glob eşleyici (`*`, `**`, `?`). Desen `/` içermiyorsa yalnız dosya
/// adına bakılır (`*.ts` her dizindeki ts dosyasını yakalar); içeriyorsa repo
/// köküne göre tam yola.
public enum ExplorerGlob {
    public static func patterns(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func matches(_ pattern: String, path: String) -> Bool {
        let normalized = pattern.hasPrefix("./") ? String(pattern.dropFirst(2)) : pattern
        let subject = normalized.contains("/")
            ? path
            : (path.split(separator: "/").last.map(String.init) ?? path)
        guard let regex = try? NSRegularExpression(pattern: regexPattern(normalized)) else { return false }
        let range = NSRange(subject.startIndex..., in: subject)
        return regex.firstMatch(in: subject, range: range) != nil
    }

    /// Glob → tam eşleşen regex. `**` her şeyi (ayraç dahil), `*` bir yol
    /// parçasını, `?` tek karakteri yakalar; geri kalanı kaçışlanır.
    static func regexPattern(_ glob: String) -> String {
        var out = "^"
        var index = glob.startIndex
        while index < glob.endIndex {
            let char = glob[index]
            let next = glob.index(after: index)
            if char == "*", next < glob.endIndex, glob[next] == "*" {
                out += ".*"
                index = glob.index(after: next)
                // `**/` → sıfır veya daha fazla dizin
                if index < glob.endIndex, glob[index] == "/" {
                    out += "/?"
                    index = glob.index(after: index)
                }
                continue
            }
            switch char {
            case "*": out += "[^/]*"
            case "?": out += "[^/]"
            default: out += NSRegularExpression.escapedPattern(for: String(char))
            }
            index = next
        }
        return out + "$"
    }
}
