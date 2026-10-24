import Foundation

/// Proje kimliğinin (karar 120) Mac ile telefonun paylaştığı kuralları: seçilebilir
/// SF Symbol'ler, emoji doğrulaması ve kök checkout başlığının sınırı. Telefon
/// görünümü düzenlediğinde (karar 132) aynı kuralla doğrular; Mac yine de her
/// gelen değeri bu kurallardan geçirir.
public enum ProjectIdentityRules {
    /// Seçilebilir SF Symbol'ler — bilinçli olarak dar (renk paletiyle aynı
    /// gerekçe). İlki varsayılandır.
    public static let symbolNames: [String] = [
        "folder", "house", "star", "bolt", "flame", "leaf",
        "gamecontroller", "hammer", "cube", "globe", "sparkles", "flag",
        "heart", "paintbrush", "book", "puzzlepiece", "terminal",
    ]

    public static var defaultSymbol: String { symbolNames[0] }

    /// Kök checkout başlığının varsayılanı ve üst sınırı (grapheme).
    public static let defaultRootTitle = "main"
    public static let rootTitleMaxLength = 24

    /// Doğrulanmış emoji: baştaki/sondaki boşluk atılır, tam olarak TEK
    /// grapheme ve emoji olarak görüntülenen bir karakter olmalı (`1`, `#`
    /// gibi emoji özelliği taşıyan ama metin olarak çizilen karakterler değil).
    public static func emoji(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first, isEmoji(character) else { return nil }
        return trimmed
    }

    /// Kırpılmış ve sınırlanmış başlık; boşsa ya da varsayılanın kendisiyse
    /// `nil` (varsayılana döner — diske `main` yazılmaz).
    public static func normalizedRootTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(rootTitleMaxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limited.isEmpty, limited != defaultRootTitle else { return nil }
        return limited
    }

    private static let variationSelector16: Unicode.Scalar = "\u{FE0F}"

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        if scalars.contains(where: \.properties.isEmojiPresentation) { return true }
        return scalars.contains(variationSelector16) && scalars.contains(where: \.properties.isEmoji)
    }
}

/// Projects sırası (karar 132): telefon görünen projelerin yeni sırasını gönderir.
public enum ProjectOrder {
    /// `path`'i `target`'ın yerine taşır (aşağı sürüklenince hedefin altına,
    /// yukarı sürüklenince üstüne düşer). Bilinmeyen yol ya da kendi üstüne
    /// bırakma sırayı değiştirmez.
    public static func moving(_ path: String, onto target: String, in paths: [String]) -> [String] {
        guard path != target, let from = paths.firstIndex(of: path),
              let to = paths.firstIndex(of: target) else { return paths }
        var result = paths
        result.remove(at: from)
        result.insert(path, at: to)
        return result
    }

    /// `visibleOrder`'daki yolları `current` içinde kapladıkları yuvalara yeni
    /// sırayla yerleştirir; listede olmayan kayıtlar (karşı tarafın görmediği
    /// favoriler) yerinde kalır, `current`'ta olmayan yollar yok sayılır.
    public static func applying(_ visibleOrder: [String], to current: [String]) -> [String] {
        let currentSet = Set(current)
        var seen = Set<String>()
        let ordered = visibleOrder.filter { currentSet.contains($0) && seen.insert($0).inserted }
        let moving = Set(ordered)
        var next = ordered.makeIterator()
        return current.map { moving.contains($0) ? (next.next() ?? $0) : $0 }
    }
}
