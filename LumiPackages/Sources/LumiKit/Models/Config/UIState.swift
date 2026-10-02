import Foundation

/// `~/.lumi/ui-state.json` şeması.
/// DİKKAT: Gerçek dosyalarda spec dışı legacy alanlar yaşar (`gridColumns`,
/// `activeView`); bunlar tipli modele girmez ama yazımda KORUNUR — Electron'la
/// gidip-gelme (karar 9) servis katmanındaki ham-dict merge'iyle sağlanır.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct UIState: Sendable, Equatable {
    public var openTabs: [String]
    public var activeTab: String?
    public var leftSidebarOpen: Bool
    public var rightSidebarOpen: Bool
    public var projectGridLayouts: [String: GridLayout]
    public var windowBounds: WindowBounds?
    public var windowMaximized: Bool?
    /// Karar 23/79 (additive): graceful quit'te canlı Claude/Codex oturumları
    /// buraya yazılır; açılışta tüketilip provider'ın resume komutuyla açılır.
    public var resumeSessions: [ResumeSession]
    /// K34 (additive): repo-dışı route kimliği (`WorkspaceRoute.content`
    /// rawValue'su). nil = route bir repo tab'ı ya da yok; o durumda
    /// `activeTab` otoritedir (karar 9).
    public var activeRoute: String?
    /// K34 (additive): panel yerleşimi (`panelLayout` + `visibleSlots` JSON
    /// anahtarları). nil = dosyada yok → `LayoutStore` eski
    /// `leftSidebarOpen`/`rightSidebarOpen` bool'larından türetir (tek seferlik
    /// migration). Eski bool'lar YAZILMAYA devam eder: `visibleSlots`'un
    /// projeksiyonudur (karar 9 — Electron'la gidip gelme korunur).
    public var panelLayout: PanelLayout?
    /// Legacy `gridColumns` alanının (number | "auto") çevirisi — yalnız OKUNUR
    /// (migration için); yazımda overlay'e girmez, ham anahtar
    /// bilinmeyen-anahtar korumasıyla diskte aynen kalır.
    public var legacyGridColumns: GridLayout?
    /// Karar 61 (additive): arayüz ölçeği (⌘+/⌘−/⌘0). nil = dosyada yok → %100.
    /// Terminal font boyutu ayrı bir ayardır ve bu ölçekle ÇARPILIR.
    public var uiScale: Double?
    /// Karar 63 (additive): arayüz yazı tipi. nil = dosyada yok → `.system`
    /// (SF Mono, eski davranış). Terminal fontu AYRI bir ayardır.
    public var uiFontFamily: UIFontFamily?
    /// Karar 65 (additive): proje yolu → o projede EN SON aktif olan checkout
    /// yolu. İndeksli kısayol bir projeye atlarken hangi checkout'un açılacağını
    /// buradan okur. Boşsa/proje yoksa projenin kendi kökü açılır.
    public var lastCheckouts: [String: String]
    /// karar 72 (additive): sağ panelin (Project Tools) seçili sekmesi —
    /// `explorer` / `agentHistory` / `sourceControl`. nil = dosyada yok →
    /// Explorer. Seçim view'ın `@State`'indeydi, panel her kapanışta (auto-reveal
    /// dahil) sıfırlanıyordu. Ham `String`: `ProjectToolsTab` LumiState'te
    /// tanımlı, LumiKit onu göremez; bilinmeyen değer okumada varsayılana iner.
    public var projectToolsTab: String?
    /// Karar 103 (additive): All Terminals görünümünün grid yerleşimi. nil =
    /// dosyada yok → varsayılan yerleşim. `projectGridLayouts`'a girmez: o
    /// sözlüğün anahtarı repo yoludur (karar 9).
    public var allTerminalsGridLayout: GridLayout?
    /// Karar 103 (additive): All Terminals'ın kart sırası — resume edilebilen
    /// terminallerin oturum kimlikleri (resume listesiyle aynı kimlik). Resume
    /// listesiyle birlikte checkpoint'te yazılır.
    public var allTerminalsOrder: [String]

    public static let defaults = UIState(
        openTabs: [],
        activeTab: nil,
        leftSidebarOpen: true,
        rightSidebarOpen: false,
        projectGridLayouts: [:],
        windowBounds: nil,
        windowMaximized: nil
    )

    public init(
        openTabs: [String],
        activeTab: String?,
        leftSidebarOpen: Bool,
        rightSidebarOpen: Bool,
        projectGridLayouts: [String: GridLayout],
        windowBounds: WindowBounds?,
        windowMaximized: Bool?,
        resumeSessions: [ResumeSession] = [],
        activeRoute: String? = nil,
        panelLayout: PanelLayout? = nil,
        legacyGridColumns: GridLayout? = nil,
        uiScale: Double? = nil,
        uiFontFamily: UIFontFamily? = nil,
        lastCheckouts: [String: String] = [:],
        projectToolsTab: String? = nil,
        allTerminalsGridLayout: GridLayout? = nil,
        allTerminalsOrder: [String] = []
    ) {
        self.openTabs = openTabs
        self.activeTab = activeTab
        self.leftSidebarOpen = leftSidebarOpen
        self.rightSidebarOpen = rightSidebarOpen
        self.projectGridLayouts = projectGridLayouts
        self.windowBounds = windowBounds
        self.windowMaximized = windowMaximized
        self.resumeSessions = resumeSessions
        self.activeRoute = activeRoute
        self.panelLayout = panelLayout
        self.legacyGridColumns = legacyGridColumns
        self.uiScale = uiScale
        self.uiFontFamily = uiFontFamily
        self.lastCheckouts = lastCheckouts
        self.projectToolsTab = projectToolsTab
        self.allTerminalsGridLayout = allTerminalsGridLayout
        self.allTerminalsOrder = allTerminalsOrder
    }
}

/// Karar 23/79: quit anında canlı olan resumable ajan oturumunun kaydı.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct ResumeSession: Sendable, Equatable {
    public let repoPath: String
    public let sessionID: String
    public let provider: AgentProvider
    /// Yalnız Codex için; thread'in rollout/auth kökünü sabitler.
    public let codexHome: String?

    public init(
        repoPath: String,
        sessionID: String,
        provider: AgentProvider = .claude,
        codexHome: String? = nil
    ) {
        self.repoPath = repoPath
        self.sessionID = sessionID
        self.provider = provider
        self.codexHome = codexHome
    }
}

/// İki eksenli grid yerleşimi (design/03; eski tek-eksenli auto/columns/rows
/// modeli emekli — `rows` yalnız okuma-migrasyonunda fit'e çevrilir):
/// (1) kolon ekseni `mode`+`count`, (2) yükseklik ekseni `heightMode`.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct GridLayout: Sendable, Equatable {
    public var mode: Mode
    public var count: Int
    public var heightMode: HeightMode
    /// Yalnız `scroll` modunda anlamlı: satır min yüksekliği = kolon genişliği ×
    /// bu oran. Büyük oran → uzun terminaller → daha çok dikey kaydırma.
    public var heightRatio: HeightRatio

    /// Kolon ekseni. `rows` EMEKLİ — yeni yazımda üretilmez, eski dosyada
    /// karşılaşılırsa ConfigCodec fit'e migrate eder.
    public enum Mode: String, Sendable {
        case auto
        case columns
    }

    /// Yükseklik politikası: `fit` hepsini pencereye sığdırır (scroll yok);
    /// `scroll` min okunur boyutu korur, taşınca dikey scroll'lanır.
    public enum HeightMode: String, Sendable {
        case fit
        case scroll
    }

    /// Scroll modunda satır min yüksekliğinin kolon genişliğine oranı.
    /// Kullanıcıya dönük etiketi LumiUI'daki presenter verir (refactor 5.9).
    public enum HeightRatio: String, Sendable, CaseIterable {
        case full   // %100 — yükseklik = genişlik
        case half   // %50
        case third  // %33

        public var multiplier: Double {
            switch self {
            case .full: return 1.0
            case .half: return 0.5
            case .third: return 1.0 / 3.0
            }
        }
    }

    public init(
        mode: Mode,
        count: Int,
        heightMode: HeightMode = .scroll,
        heightRatio: HeightRatio = .half
    ) {
        self.mode = mode
        self.count = count
        self.heightMode = heightMode
        self.heightRatio = heightRatio
    }
}

/// Pencere konumu/boyutu (`ui-state.json` → `windowBounds`). Tam sayı değerler
/// diske "580" olarak yazılır ("580.0" değil) — Electron paritesi, karar 9.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct WindowBounds: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
