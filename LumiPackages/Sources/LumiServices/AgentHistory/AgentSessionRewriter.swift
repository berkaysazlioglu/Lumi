import Foundation

/// İçe aktarımda kayıtlardaki metinleri yeniden yazar: kaynak proje kökü →
/// hedef proje kökü ve (çakışmada) eski oturum kimliği → yeni kimlik.
///
/// Değiştirme JSON ağacında **her string değer** üzerinde çalışır — `cwd`
/// alanı, araç girdilerindeki mutlak yollar ve Codex `payload.cwd` dahil.
/// Kök yolu yalnız bir yol sınırında eşleşir (`/a/Lumi` → `/a/Lumi2`'ye dokunmaz).
struct AgentSessionRewriter {
    struct Replacement: Equatable {
        let from: String
        let to: String
        /// `true`: eşleşmenin ardından `/`, string sonu ya da alfanümerik olmayan
        /// bir karakter gelmeli (yol kökü). `false`: düz alt-dizi (oturum kimliği).
        let requiresPathBoundary: Bool
    }

    let replacements: [Replacement]

    func rewrite(_ records: [[String: Any]]) -> [[String: Any]] {
        guard !replacements.isEmpty else { return records }
        return records.map { rewriteValue($0) as? [String: Any] ?? $0 }
    }

    func rewrite(_ object: [String: Any]?) -> [String: Any]? {
        guard let object, !replacements.isEmpty else { return object }
        return rewriteValue(object) as? [String: Any]
    }

    func rewrite(_ text: String) -> String {
        replacements.reduce(text) { partial, replacement in
            replacement.requiresPathBoundary
                ? Self.replacePathRoot(partial, from: replacement.from, to: replacement.to)
                : partial.replacingOccurrences(of: replacement.from, with: replacement.to)
        }
    }

    private func rewriteValue(_ value: Any) -> Any {
        switch value {
        case let string as String: return rewrite(string)
        case let array as [Any]: return array.map(rewriteValue)
        case let dictionary as [String: Any]: return dictionary.mapValues(rewriteValue)
        default: return value
        }
    }

    static func replacePathRoot(_ text: String, from: String, to: String) -> String {
        guard !from.isEmpty, from != to, text.contains(from) else { return text }
        var result = ""
        var searchStart = text.startIndex
        while let range = text.range(of: from, range: searchStart..<text.endIndex) {
            result += text[searchStart..<range.lowerBound]
            let next = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let isBoundary = next.map { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" } ?? true
            result += isBoundary ? to : from
            searchStart = range.upperBound
        }
        result += text[searchStart..<text.endIndex]
        return result
    }
}
