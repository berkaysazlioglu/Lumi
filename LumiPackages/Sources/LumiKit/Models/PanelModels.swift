import Foundation

/// Kabuğun panel yuvaları (K33, Faz 6.2).
///
/// Yuva SAYISI kapalıdır (sol/sağ/alt bir pencere kabuğunun coğrafyasıdır),
/// yuvadaki ÖĞE kümesi ise açıktır — bkz. `PanelItemID`.
public enum PanelSlot: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case bottom
    /// Karar 124: orta alan ile sağ yuvanın ARASI — orchestrator paneli.
    case innerRight

    /// Karar 124: sağ kenarı paylaşan iki yuva — `PanelLayout.exclusiveRightPanels`
    /// açıkken biri açılınca diğeri kapanır.
    public var rightEdgePartner: PanelSlot? {
        switch self {
        case .right: return .innerRight
        case .innerRight: return .right
        case .left, .bottom: return nil
        }
    }
}

/// Bir panel öğesinin kimliği (K33).
///
/// `ContentRouteID` ile aynı kalıp: `enum` yerine `RawRepresentable` string id,
/// çünkü öğe kümesi bir registry'den beslenir ve yeni özellik LumiKit'teki bir
/// enum'u (ve ondan türeyen exhaustive switch'leri) değiştirmek zorunda
/// kalmamalıdır (OCP). Düz string olduğu için persist tarafı da additive bir
/// alana sığar.
public struct PanelItemID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension PanelItemID {
    static let projects = PanelItemID("projects")
    static let projectTools = PanelItemID("projectTools")
    /// Karar 124: orchestrator'ın docked paneli.
    static let orchestrator = PanelItemID("orchestrator")

    /// Sol panelin Tasks/Remote sekmeleri (karar 55 — eski `sessions` öğesinin
    /// yeri).
    static let tasks = PanelItemID("tasks")
    /// Aktif repo'nun dosya ağacı ("Project Context").
    static let fileTree = PanelItemID("fileTree")
    /// Git branch + commit zaman çizelgesi.
    static let gitCommits = PanelItemID("gitCommits")
    /// Git çalışma kopyası değişiklikleri + commit composer.
    static let gitChanges = PanelItemID("gitChanges")
}

/// Panel yerleşimi: hangi öğe hangi yuvada, hangi yuva görünür, yuva
/// genişlikleri (K33/K34) ve hangi yuvanın kenar hover'ıyla içeriğin ÜSTÜNE
/// açıldığı (`autoRevealSlots`, karar 44).
///
/// **Değişmez (immutable):** her mutasyon YENİ bir değer döndürür; `LayoutStore`
/// tek alanı değiştirip persist eder. "Bir öğeyi soldan sağa taşımak" tek bir
/// `moving(_:to:index:)` çağrısıdır.
public struct PanelLayout: Equatable, Sendable {
    /// Sol/alt yuva varsayılan genişliği (bugünkü sabit 280px sidebar).
    public static let defaultWidth: Double = 280
    /// Sağ proje paneli daha geniş açılır (karar 42): Explorer içerik araması,
    /// commit graph'ı ve Agent History kartı 280'de sıkışıyordu.
    public static let projectPanelWidth: Double = 340
    /// K42 migration için: kabuk hiç resize sunmadığından kalıcı dosyadaki
    /// eski 280 değeri daima eski default'tur, yeni default'a taşınır.
    public static let legacyProjectPanelWidth: Double = 280

    /// Karar 124: orchestrator paneli Codex TUI'sine ~60 kolon bırakır.
    public static let orchestratorPanelWidth: Double = 460

    /// Yuvaya göre varsayılan genişlik.
    public static func defaultWidth(for slot: PanelSlot) -> Double {
        switch slot {
        case .right: return projectPanelWidth
        case .innerRight: return orchestratorPanelWidth
        case .left, .bottom: return defaultWidth
        }
    }

    /// Karar 125: yuva başına sürükleme aralığı. Sağ yuvanın alt sınırı
    /// `legacyProjectPanelWidth`'in (280) üstündedir — K42 migration'ı diskteki
    /// 280'i eski default sayar; sürüklemeyle 280 üretilememeli.
    public static func widthRange(for slot: PanelSlot) -> ClosedRange<Double> {
        switch slot {
        case .left: return 200...480
        case .right: return 300...640
        // Codex TUI'si ~45 kolonun altında okunmaz.
        case .innerRight: return 360...800
        case .bottom: return 180...640
        }
    }

    /// Karar 125: sürükleme orta alanı bundan dar bırakamaz.
    public static let minContentWidth: Double = 360

    /// Yatayda yan yana duran yuvalar (alt yuva hariç).
    public static let horizontalSlots: [PanelSlot] = [.left, .innerRight, .right]

    public private(set) var slots: [PanelSlot: [PanelItemID]]
    public private(set) var visibleSlots: Set<PanelSlot>
    public private(set) var widths: [PanelSlot: Double]
    /// Karar 44: yuva GİZLİYKEN fare pencerenin o kenarına gelince yuva orta
    /// alanı daraltmadan, içeriğin üstünde geçici olarak açılır. Görünürlükten
    /// bağımsız bir tercihtir: yuva sabitlenmişse (visible) etkisi yoktur.
    public private(set) var autoRevealSlots: Set<PanelSlot>
    /// Karar 124: sağ kenarı paylaşan yuvalardan (`rightEdgePartner`) yalnız
    /// biri açık durur — biri açılınca diğeri kapanır. Varsayılan açık.
    public private(set) var exclusiveRightPanels: Bool

    public init(
        slots: [PanelSlot: [PanelItemID]],
        visibleSlots: Set<PanelSlot>,
        widths: [PanelSlot: Double],
        autoRevealSlots: Set<PanelSlot> = [],
        exclusiveRightPanels: Bool = true
    ) {
        self.slots = slots
        self.visibleSlots = visibleSlots
        self.widths = widths
        self.autoRevealSlots = autoRevealSlots
        self.exclusiveRightPanels = exclusiveRightPanels
    }

    /// Sol = Sessions, sağ = sekmeli Project Tools; sol açık, sağ kapalı.
    public static let defaults = PanelLayout(
        slots: [
            .left: [.tasks, .projects],
            .right: [.projectTools],
            .bottom: [],
            .innerRight: [.orchestrator],
        ],
        visibleSlots: [.left],
        widths: [
            .left: defaultWidth(for: .left),
            .right: defaultWidth(for: .right),
            .bottom: defaultWidth(for: .bottom),
            .innerRight: defaultWidth(for: .innerRight),
        ]
    )

    /// K34 tek seferlik migration: yeni `panelLayout` anahtarı yokken görünürlük
    /// eski `leftSidebarOpen`/`rightSidebarOpen` bool'larından türetilir.
    public static func migrating(leftOpen: Bool, rightOpen: Bool) -> PanelLayout {
        var visible: Set<PanelSlot> = []
        if leftOpen { visible.insert(.left) }
        if rightOpen { visible.insert(.right) }
        return PanelLayout(
            slots: defaults.slots,
            visibleSlots: visible,
            widths: defaults.widths
        )
    }

    // MARK: - Okumalar

    public func items(in slot: PanelSlot) -> [PanelItemID] {
        slots[slot] ?? []
    }

    public func isVisible(_ slot: PanelSlot) -> Bool {
        visibleSlots.contains(slot)
    }

    /// Karar 125: diskteki eski değer (eski genel 180…640 aralığı) yeni yuva
    /// aralığına okunurken oturtulur.
    public func width(for slot: PanelSlot) -> Double {
        Self.clamp(widths[slot] ?? Self.defaultWidth(for: slot), to: Self.widthRange(for: slot))
    }

    public func isAutoReveal(_ slot: PanelSlot) -> Bool {
        autoRevealSlots.contains(slot)
    }

    /// Öğenin bulunduğu yuva (hiçbir yuvada değilse `nil`).
    public func slot(of item: PanelItemID) -> PanelSlot? {
        for slot in PanelSlot.allCases where items(in: slot).contains(item) {
            return slot
        }
        return nil
    }

    // MARK: - Mutasyonlar (hepsi yeni değer döndürür)

    /// Karar 124: `exclusiveRightPanels` açıkken sağ kenar ortağı kapanır.
    public func settingVisible(_ slot: PanelSlot, _ visible: Bool) -> PanelLayout {
        var copy = self
        if visible {
            copy.visibleSlots.insert(slot)
            if exclusiveRightPanels, let partner = slot.rightEdgePartner {
                copy.visibleSlots.remove(partner)
            }
        } else {
            copy.visibleSlots.remove(slot)
        }
        return copy
    }

    public func togglingVisible(_ slot: PanelSlot) -> PanelLayout {
        settingVisible(slot, !isVisible(slot))
    }

    /// Karar 44: kenar hover'ıyla açılma tercihi (görünürlüğe dokunmaz).
    public func settingAutoReveal(_ slot: PanelSlot, _ enabled: Bool) -> PanelLayout {
        var copy = self
        if enabled {
            copy.autoRevealSlots.insert(slot)
        } else {
            copy.autoRevealSlots.remove(slot)
        }
        return copy
    }

    /// Karar 124: tercih açılırken iki ortak da açıksa orchestrator yuvası
    /// kapanır — "yalnız biri açık" kuralı kurulduğu anda geçerli olsun.
    public func settingExclusiveRightPanels(_ enabled: Bool) -> PanelLayout {
        var copy = self
        copy.exclusiveRightPanels = enabled
        if enabled, isVisible(.right), isVisible(.innerRight) {
            copy.visibleSlots.remove(.innerRight)
        }
        return copy
    }

    /// Genişlik yuvanın `widthRange(for:)` aralığına kırpılır.
    public func settingWidth(_ width: Double, for slot: PanelSlot) -> PanelLayout {
        var copy = self
        copy.widths[slot] = Self.clamp(width, to: Self.widthRange(for: slot))
        return copy
    }

    /// Karar 125: sürüklenen genişlik — yuva aralığına, ayrıca pencere
    /// genişliği biliniyorsa orta alana `minContentWidth` kalacak şekilde
    /// kırpılır (diğer görünür yan yuvalar düşülür). Pencere çok darsa yuvanın
    /// alt sınırı kazanır — panel okunmaz hale gelmez.
    public func resizedWidth(_ width: Double, for slot: PanelSlot, containerWidth: Double?) -> Double {
        let range = Self.widthRange(for: slot)
        guard let containerWidth else { return Self.clamp(width, to: range) }
        let others = Self.horizontalSlots
            .filter { $0 != slot && isVisible($0) }
            .reduce(0) { $0 + self.width(for: $1) }
        let upper = max(range.lowerBound, min(range.upperBound, containerWidth - others - Self.minContentWidth))
        return Self.clamp(width, to: range.lowerBound...upper)
    }

    /// Karar 125: Settings ▸ Appearance ▸ Reset — tüm yuvalar varsayılan genişliğe.
    public func resettingWidths() -> PanelLayout {
        var copy = self
        for slot in PanelSlot.allCases {
            copy.widths[slot] = Self.defaultWidth(for: slot)
        }
        return copy
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Öğeyi hedef yuvaya taşır (kaynak yuvadan düşer). `index` nil ise sona
    /// eklenir; aralık dışı index kırpılır. **Soldan sağa taşıma bu tek
    /// çağrıdır.**
    public func moving(_ item: PanelItemID, to slot: PanelSlot, index: Int? = nil) -> PanelLayout {
        var copy = self
        for existing in PanelSlot.allCases {
            copy.slots[existing] = copy.items(in: existing).filter { $0 != item }
        }
        var target = copy.items(in: slot)
        let position = min(max(index ?? target.count, 0), target.count)
        target.insert(item, at: position)
        copy.slots[slot] = target
        return copy
    }

    /// Karar 55 migration: kalıcı yerleşimdeki `sessions` öğesi `tasks` ile
    /// AYNI SIRADA değiştirilir — kullanıcı öğeyi taşımışsa Tasks da o yuvada
    /// doğar. Hiç `sessions` kaydı yoksa (ya da `tasks` zaten varsa) yerleşim
    /// olduğu gibi kalır; kayıtsız öğe zaten `defaultSlot`'una düşer.
    public func migratingSessionsToTasks() -> PanelLayout {
        let legacy = PanelItemID("sessions")
        guard slot(of: .tasks) == nil, let slot = slot(of: legacy),
              var items = slots[slot], let index = items.firstIndex(of: legacy) else {
            return self
        }
        items[index] = .tasks
        var copy = self
        copy.slots[slot] = items
        return copy
    }

    /// Projects/Tasks sırasının ilk sürümden yeni varsayılan sıraya geçişi.
    /// Projects sol yuvada Tasks'ın önündeyse, Tasks'ın hemen arkasına
    /// taşınır. Diğer yuvalar ve yerleşim metadatası değişmez.
    public func migratingProjectsAfterTasks() -> PanelLayout {
        guard let left = slots[.left],
              let projectsIndex = left.firstIndex(of: .projects),
              let anchorIndex = left.firstIndex(of: .tasks),
              projectsIndex < anchorIndex else {
            return self
        }

        var reordered = left
        reordered.remove(at: projectsIndex)
        guard let updatedAnchorIndex = reordered.firstIndex(of: .tasks) else {
            return self
        }
        reordered.insert(.projects, at: updatedAnchorIndex + 1)

        var copy = self
        copy.slots[.left] = reordered
        return copy
    }
}
