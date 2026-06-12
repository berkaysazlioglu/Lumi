import Foundation

/// `~/.lumi/config.json` şeması (spec/13 §1.1; gerçek dosyayla doğrulandı).
/// Alan adları diskteki JSON anahtarlarıyla birebir aynıdır (karar 9).
public struct AppConfig: Codable, Sendable, Equatable {
    public var projectsRoot: String
    public var additionalPaths: [AdditionalPath]
    public var aiProvider: AgentProvider
    public var maxTerminals: Int
    public var theme: String
    public var terminalFontSize: Int
    public var notifications: NotificationSettings

    public static let defaults = AppConfig(
        projectsRoot: "",
        additionalPaths: [],
        aiProvider: .claude,
        maxTerminals: 12,
        theme: "dark",
        terminalFontSize: 13,
        notifications: .defaults
    )

    public init(
        projectsRoot: String,
        additionalPaths: [AdditionalPath],
        aiProvider: AgentProvider,
        maxTerminals: Int,
        theme: String,
        terminalFontSize: Int,
        notifications: NotificationSettings
    ) {
        self.projectsRoot = projectsRoot
        self.additionalPaths = additionalPaths
        self.aiProvider = aiProvider
        self.maxTerminals = maxTerminals
        self.theme = theme
        self.terminalFontSize = terminalFontSize
        self.notifications = notifications
    }
}

public struct AdditionalPath: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var path: String
    public var type: PathType
    public var label: String?

    public enum PathType: String, Codable, Sendable {
        case root
        case repo
    }

    public init(id: String, path: String, type: PathType, label: String? = nil) {
        self.id = id
        self.path = path
        self.type = type
        self.label = label
    }
}

public struct NotificationSettings: Codable, Sendable, Equatable {
    public var unseenEnabled: Bool
    public var unseenIntervalMinutes: Int
    public var seenEnabled: Bool
    public var seenIntervalMinutes: Int

    public static let defaults = NotificationSettings(
        unseenEnabled: true,
        unseenIntervalMinutes: 1,
        seenEnabled: true,
        seenIntervalMinutes: 5
    )

    public init(
        unseenEnabled: Bool,
        unseenIntervalMinutes: Int,
        seenEnabled: Bool,
        seenIntervalMinutes: Int
    ) {
        self.unseenEnabled = unseenEnabled
        self.unseenIntervalMinutes = unseenIntervalMinutes
        self.seenEnabled = seenEnabled
        self.seenIntervalMinutes = seenIntervalMinutes
    }
}

/// `~/.lumi/ui-state.json` şeması (spec/13 §1.3).
/// DİKKAT: Gerçek dosyalarda spec dışı legacy alanlar yaşar (`gridColumns`,
/// `activeView`); bunlar tipli modele girmez ama yazımda KORUNUR — Electron'la
/// gidip-gelme (karar 9) servis katmanındaki ham-dict merge'iyle sağlanır.
public struct UIState: Codable, Sendable, Equatable {
    public var openTabs: [String]
    public var activeTab: String?
    public var leftSidebarOpen: Bool
    public var rightSidebarOpen: Bool
    public var projectGridLayouts: [String: GridLayout]
    public var windowBounds: WindowBounds?
    public var windowMaximized: Bool?
    /// Legacy `gridColumns` alanının (number | "auto") çevirisi — yalnız OKUNUR
    /// (spec/21 §13 migration'ı için); yazımda overlay'e girmez, ham anahtar
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
        legacyGridColumns: GridLayout? = nil
    ) {
        self.openTabs = openTabs
        self.activeTab = activeTab
        self.leftSidebarOpen = leftSidebarOpen
        self.rightSidebarOpen = rightSidebarOpen
        self.projectGridLayouts = projectGridLayouts
        self.windowBounds = windowBounds
        self.windowMaximized = windowMaximized
        self.legacyGridColumns = legacyGridColumns
    }
}

/// İki eksenli grid yerleşimi (design/03; eski tek-eksenli auto/columns/rows
/// modeli emekli — `rows` yalnız okuma-migrasyonunda fit'e çevrilir):
/// (1) kolon ekseni `mode`+`count`, (2) yükseklik ekseni `heightMode`.
public struct GridLayout: Codable, Sendable, Equatable {
    public var mode: Mode
    public var count: Int
    public var heightMode: HeightMode

    /// Kolon ekseni. `rows` EMEKLİ — yeni yazımda üretilmez, eski dosyada
    /// karşılaşılırsa ConfigCodec fit'e migrate eder.
    public enum Mode: String, Codable, Sendable {
        case auto
        case columns
    }

    /// Yükseklik politikası: `fit` hepsini pencereye sığdırır (scroll yok);
    /// `scroll` min okunur boyutu korur, taşınca dikey scroll'lanır.
    public enum HeightMode: String, Codable, Sendable {
        case fit
        case scroll
    }

    public init(mode: Mode, count: Int, heightMode: HeightMode = .scroll) {
        self.mode = mode
        self.count = count
        self.heightMode = heightMode
    }
}

public struct WindowBounds: Codable, Sendable, Equatable {
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
