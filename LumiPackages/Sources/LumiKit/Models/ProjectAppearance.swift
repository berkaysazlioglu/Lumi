import Foundation

/// Projenin görünümü (karar 120): kimlik rengi + Projects'teki proje
/// satırının ikonu ve kök checkout'un başlığı. Tüm alanlar opsiyoneldir; `nil` alan bugünkü
/// görünümdür (renksiz, `folder`, `main`). Değerler bu tipin kurucularından
/// geçtiği için her zaman doğrulanmıştır — codec ve store aynı kuralı kullanır.
public struct ProjectAppearance: Equatable, Sendable {
    public var color: ProjectColor?
    /// `nil` → varsayılan `folder`. Varsayılan ikon seçilirse `nil` tutulur.
    public private(set) var icon: ProjectIcon?
    /// `nil` → `main`. Kırpılmış ve sınırlanmış; boş başlık tutulmaz.
    public private(set) var rootTitle: String?

    public init(color: ProjectColor? = nil, icon: ProjectIcon? = nil, rootTitle: String? = nil) {
        self.color = color
        setIcon(icon)
        setRootTitle(rootTitle)
    }

    public static let none = ProjectAppearance()

    public var isEmpty: Bool { color == nil && icon == nil && rootTitle == nil }

    /// Projects satırında çizilecek ikon (varsayılan dahil).
    public var resolvedIcon: ProjectIcon { icon ?? .default }
    /// Kök checkout'un görünen başlığı.
    public var resolvedRootTitle: String { rootTitle ?? ProjectRootTitle.defaultTitle }

    public mutating func setIcon(_ icon: ProjectIcon?) {
        self.icon = icon == .default ? nil : icon
    }

    public mutating func setRootTitle(_ raw: String?) {
        rootTitle = raw.flatMap(ProjectRootTitle.normalized)
    }
}

/// Proje ikonu (Projects'te proje adının başında): izin listesindeki bir SF Symbol ya da tek bir emoji.
/// Diskte `sf:<ad>` / `emoji:<karakter>` olarak durur.
public enum ProjectIcon: Equatable, Hashable, Sendable {
    case symbol(String)
    case emoji(String)

    /// Bugünkü sabit ikon.
    public static let `default` = ProjectIcon.symbol("folder")

    /// Seçilebilir SF Symbol'ler — bilinçli olarak dar (renk paletiyle aynı
    /// gerekçe). İlki varsayılandır.
    public static let symbolNames: [String] = [
        "folder", "house", "star", "bolt", "flame", "leaf",
        "gamecontroller", "hammer", "cube", "globe", "sparkles", "flag",
        "heart", "paintbrush", "book", "puzzlepiece", "terminal",
    ]

    /// Doğrulanmış SF Symbol; izin listesinde değilse `nil`.
    public static func symbol(named name: String) -> ProjectIcon? {
        symbolNames.contains(name) ? .symbol(name) : nil
    }

    /// Doğrulanmış emoji: baştaki/sondaki boşluk atılır, tam olarak TEK
    /// grapheme ve emoji olarak görüntülenen bir karakter olmalı (`1`, `#`
    /// gibi emoji özelliği taşıyan ama metin olarak çizilen karakterler değil).
    public static func emoji(from raw: String) -> ProjectIcon? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first, isEmoji(character) else { return nil }
        return .emoji(trimmed)
    }

    private static let variationSelector16: Unicode.Scalar = "\u{FE0F}"

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        if scalars.contains(where: \.properties.isEmojiPresentation) { return true }
        return scalars.contains(variationSelector16) && scalars.contains(where: \.properties.isEmoji)
    }

    /// Diskteki değer.
    public var persisted: String {
        switch self {
        case .symbol(let name): "sf:\(name)"
        case .emoji(let value): "emoji:\(value)"
        }
    }

    /// Diskten okuma — geçersiz değer `nil`.
    public init?(persisted raw: String) {
        if raw.hasPrefix("sf:"), let icon = Self.symbol(named: String(raw.dropFirst(3))) {
            self = icon
        } else if raw.hasPrefix("emoji:"), let icon = Self.emoji(from: String(raw.dropFirst(6))) {
            self = icon
        } else {
            return nil
        }
    }
}

/// Kök checkout başlığının kuralı.
public enum ProjectRootTitle {
    /// Bugünkü sabit başlık. Telefon/orchestrator ağacı (`ProjectTree.originalTitle`)
    /// bundan bağımsızdır ve değişmez.
    public static let defaultTitle = "main"
    /// Panel satırına sığan makul üst sınır (grapheme).
    public static let maxLength = 24

    /// Kırpılmış ve sınırlanmış başlık; boşsa ya da varsayılanın kendisiyse
    /// `nil` (varsayılana döner — diske `main` yazılmaz).
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limited.isEmpty, limited != defaultTitle else { return nil }
        return limited
    }
}

public extension AppConfig {
    /// Proje kökü → renk (renksiz projeler yok) — terminal renk çözümünün girdisi.
    var projectColors: [String: ProjectColor] { projectAppearance.compactMapValues(\.color) }

    /// Projenin görünümü; kaydı yoksa `.none` (bugünkü görünüm).
    func appearance(ofProject path: String) -> ProjectAppearance {
        projectAppearance[path] ?? .none
    }
}
