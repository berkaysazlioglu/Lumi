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
    /// Karar 23 (additive): graceful quit'te canlı claude oturumları buraya
    /// yazılır; açılışta tüketilir (okunur + boşaltılır) ve `claude --resume`
    /// ile aynı chat'ten devam edilir. Boş liste = devam edilecek oturum yok.
    public var resumeSessions: [ResumeSession]
    /// K34 (additive): repo-dışı route kimliği (`WorkspaceRoute.content`
    /// rawValue'su). nil = route bir repo tab'ı ya da yok; o durumda
    /// `activeTab` otoritedir (karar 9).
    public var activeRoute: String?
    /// Legacy `gridColumns` alanının (number | "auto") çevirisi — yalnız OKUNUR
    /// (migration için); yazımda overlay'e girmez, ham anahtar
    /// bilinmeyen-anahtar korumasıyla diskte aynen kalır.
    public var legacyGridColumns: GridLayout?

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
        legacyGridColumns: GridLayout? = nil
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
        self.legacyGridColumns = legacyGridColumns
    }
}

/// Karar 23: quit anında canlı olan bir claude oturumunun kaydı — açılışta
/// `claude --resume <sessionID>` ile aynı repo'da devam edilir.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct ResumeSession: Sendable, Equatable {
    public let repoPath: String
    public let sessionID: String

    public init(repoPath: String, sessionID: String) {
        self.repoPath = repoPath
        self.sessionID = sessionID
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
