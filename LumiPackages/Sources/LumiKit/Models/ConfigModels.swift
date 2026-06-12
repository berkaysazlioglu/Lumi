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
    /// macOS stem-darkening (CG font smoothing). false = ince çizgiler
    /// (v1/xterm.js `-webkit-font-smoothing: antialiased` paritesi).
    /// Additive alan (karar 9): eski config'lerde yoksa false kabul edilir.
    public var terminalFontSmoothing: Bool
    /// Renk teması preset id'si (`TerminalTheme.preset(id:)` ile çözülür).
    /// Additive (karar 9): yoksa "lumi"; bilinmeyen id → lumi.
    public var terminalTheme: String
    /// Terminal font ailesi. Boş = bundle'daki JetBrains Mono (default).
    /// Additive (karar 9): yoksa "".
    public var terminalFontFamily: String
    /// Caret şekli (`TerminalCursorShape.rawValue`). Additive (karar 9):
    /// yoksa/geçersizse "block".
    public var terminalCursorStyle: String
    /// Caret yanıp-sönmesi. Additive (karar 9): yoksa true.
    public var terminalCursorBlink: Bool
    public var notifications: NotificationSettings
    /// Zamanlanmış oturum tetikleyicisi (günlük belirli saatte Claude oturumunu
    /// başlatan otomatik prompt). Additive (karar 9): yoksa kapalı default.
    public var sessionTrigger: SessionTrigger

    public static let defaults = AppConfig(
        projectsRoot: "",
        additionalPaths: [],
        aiProvider: .claude,
        maxTerminals: 12,
        theme: "dark",
        terminalFontSize: 13,
        terminalFontSmoothing: false,
        terminalTheme: "lumi",
        terminalFontFamily: "",
        terminalCursorStyle: TerminalCursorShape.block.rawValue,
        terminalCursorBlink: true,
        notifications: .defaults,
        sessionTrigger: .defaults
    )

    public init(
        projectsRoot: String,
        additionalPaths: [AdditionalPath],
        aiProvider: AgentProvider,
        maxTerminals: Int,
        theme: String,
        terminalFontSize: Int,
        terminalFontSmoothing: Bool,
        terminalTheme: String,
        terminalFontFamily: String,
        terminalCursorStyle: String,
        terminalCursorBlink: Bool,
        notifications: NotificationSettings,
        sessionTrigger: SessionTrigger = .defaults
    ) {
        self.projectsRoot = projectsRoot
        self.additionalPaths = additionalPaths
        self.aiProvider = aiProvider
        self.maxTerminals = maxTerminals
        self.theme = theme
        self.terminalFontSize = terminalFontSize
        self.terminalFontSmoothing = terminalFontSmoothing
        self.terminalTheme = terminalTheme
        self.terminalFontFamily = terminalFontFamily
        self.terminalCursorStyle = terminalCursorStyle
        self.terminalCursorBlink = terminalCursorBlink
        self.notifications = notifications
        self.sessionTrigger = sessionTrigger
    }
}

/// Günlük zamanlanmış oturum tetikleyicisi (`~/.lumi/config.json` →
/// `sessionTrigger`). Uygulama açıkken her gün `hour:minute` saatinde, bekleyen
/// bir Claude oturumuna `prompt` enjekte ederek 5 saatlik kullanım penceresini
/// başlatır. Saat kullanıcının yerel takvimine göredir.
public struct SessionTrigger: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// 0–23 (yerel saat).
    public var hour: Int
    /// 0–59.
    public var minute: Int
    /// Enjekte edilen prompt; boşsa "hello"ya düşer.
    public var prompt: String

    public static let defaultPrompt = "hello"

    public static let defaults = SessionTrigger(
        enabled: false,
        hour: 9,
        minute: 0,
        prompt: defaultPrompt
    )

    public init(enabled: Bool, hour: Int, minute: Int, prompt: String) {
        self.enabled = enabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.prompt = prompt
    }

    /// Enjeksiyonda kullanılacak güvenli prompt (boş/whitespace → default).
    public var effectivePrompt: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPrompt : trimmed
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
    /// Yalnız `scroll` modunda anlamlı: satır min yüksekliği = kolon genişliği ×
    /// bu oran. Büyük oran → uzun terminaller → daha çok dikey kaydırma.
    public var heightRatio: HeightRatio

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

    /// Scroll modunda satır min yüksekliğinin kolon genişliğine oranı.
    public enum HeightRatio: String, Codable, Sendable, CaseIterable {
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

        public var label: String {
            switch self {
            case .full: return "100%"
            case .half: return "50%"
            case .third: return "33%"
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
