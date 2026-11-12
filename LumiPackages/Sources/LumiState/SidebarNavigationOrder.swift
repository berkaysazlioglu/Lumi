import LumiKit

/// Sol üst bölümün (All Terminals / Custom View'lar / Tasks / Remote) tek
/// satırı (karar 151). Sıralama bu satırların tamamı arasındadır — view'lar
/// kendi aralarında değil, bölümdeki her satırla yer değiştirebilir.
public enum SidebarNavigationItem: Hashable, Sendable {
    case allTerminals
    case customView(CustomViewID)
    case section(TasksPanelSection)

    private static let customViewPrefix = "view:"
    private static let allTerminalsKey = "allTerminals"

    /// `ui-state` → `sidebarNavigationOrder` girdisi ve sürükleme yükü.
    public var key: String {
        switch self {
        case .allTerminals: Self.allTerminalsKey
        case .customView(let id): Self.customViewPrefix + id.rawValue
        case .section(let section): section.rawValue
        }
    }

    public init?(key: String) {
        if key == Self.allTerminalsKey {
            self = .allTerminals
        } else if key.hasPrefix(Self.customViewPrefix) {
            let raw = String(key.dropFirst(Self.customViewPrefix.count))
            guard !raw.isEmpty else { return nil }
            self = .customView(CustomViewID(rawValue: raw))
        } else if let section = TasksPanelSection(rawValue: key) {
            self = .section(section)
        } else {
            return nil
        }
    }
}

/// Bölümün görünen sırası — saf fonksiyonlar (karar 151).
public enum SidebarNavigationOrder {
    /// Hiç sıralanmamış bölüm: All Terminals, view'lar (doğuş sırasıyla),
    /// Tasks, Remote — karar 135'teki düzen.
    public static func defaultItems(views: [CustomViewID]) -> [SidebarNavigationItem] {
        [.allTerminals] + views.map(SidebarNavigationItem.customView)
            + TasksPanelSection.allCases.map(SidebarNavigationItem.section)
    }

    /// Kayıtlı sıra canlı satırlarla birleşir: artık var olmayan (silinmiş
    /// view) ya da bozuk anahtarlar düşer; kayıtta olmayan satır (yeni doğan
    /// view, yeni bölüm) varsayılan düzendeki öncülünün hemen arkasına —
    /// öncülü yoksa başa — girer. Böylece yeni view diğer view'ların yanında
    /// doğar.
    public static func resolve(saved: [String], views: [CustomViewID]) -> [SidebarNavigationItem] {
        let defaults = defaultItems(views: views)
        let live = Set(defaults)
        var seen = Set<SidebarNavigationItem>()
        var result = saved.compactMap(SidebarNavigationItem.init(key:)).filter {
            live.contains($0) && seen.insert($0).inserted
        }
        for (index, item) in defaults.enumerated() where !seen.contains(item) {
            let predecessor = defaults[..<index].last { seen.contains($0) }
            let position = predecessor.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(item, at: position)
            seen.insert(item)
        }
        return result
    }

    /// `moving` satırı `target`'ın yerine geçer (aşağı sürüklenince hedefin
    /// arkasına, yukarı sürüklenince önüne düşer). Değişiklik yoksa `nil`.
    public static func moving(
        _ moving: SidebarNavigationItem,
        onto target: SidebarNavigationItem,
        in items: [SidebarNavigationItem]
    ) -> [SidebarNavigationItem]? {
        guard moving != target,
              let from = items.firstIndex(of: moving),
              let to = items.firstIndex(of: target) else { return nil }
        var result = items
        result.remove(at: from)
        result.insert(moving, at: to)
        return result
    }
}
