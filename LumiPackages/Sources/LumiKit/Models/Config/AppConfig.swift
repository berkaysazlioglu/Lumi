import Foundation

/// `~/.lumi/config.json` şeması (gerçek dosyayla doğrulandı).
/// Alan adları diskteki JSON anahtarlarıyla birebir aynıdır (karar 9).
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.** Tip `Codable`
/// DEĞİLDİR: disk formatı ham-dict + tipli-overlay merge'iyle yazılır
/// (bilinmeyen/legacy anahtarlar korunur). Bir `Codable` conformance'ı burada
/// "encode edilebilir" yanılsaması yaratır ve karar 9'u sessizce ihlal eden bir
/// yazım yolunun kapısını açar.
public struct AppConfig: Sendable, Equatable {
    public var projectsRoot: String
    public var additionalPaths: [AdditionalPath]
    public var aiProvider: AgentProvider
    public var theme: String
    public var terminalFontSize: Int
    /// Terminal font ailesi. Boş = bundle'daki JetBrains Mono (default).
    /// Additive (karar 9): yoksa "".
    public var terminalFontFamily: String
    /// Caret şekli (`TerminalCursorShape.rawValue`). Additive (karar 9):
    /// yoksa/geçersizse "block".
    public var terminalCursorStyle: String
    /// Caret yanıp-sönmesi. Additive (karar 9): yoksa true.
    public var terminalCursorBlink: Bool
    public var notifications: NotificationSettings
    /// Mesaj gönderilen (working'e geçen) terminal otomatik minimize edilir;
    /// turn bitince ya da girdi beklenince otomatik restore edilir (karar 24).
    /// Additive (karar 9): yoksa kapalı default.
    public var autoMinimizeOnSend: Bool
    /// Zamanlanmış oturum tetikleyicisi (günlük belirli saatte Claude oturumunu
    /// başlatan otomatik prompt). Additive (karar 9): yoksa kapalı default.
    public var sessionTrigger: SessionTrigger
    /// Kullanım göstergesinin otomatik tazelenmesi (opt-in, karar 20). Additive
    /// (karar 9): yoksa kapalı default.
    public var usageAutoRefresh: UsageAutoRefresh
    /// Topbar'da hangi sağlayıcıların kullanım göstergesinin görüneceği
    /// (karar 32). Additive (karar 9): yoksa claude açık / codex kapalı.
    public var usageIndicators: UsageIndicators
    /// Alt bardaki "Keep computer awake" modu (karar 43). Additive (karar 9):
    /// yoksa/geçersizse `off`.
    public var computerAwakeMode: ComputerAwakeMode
    /// Claude/Codex hook'larının kurulup terminal durumunun hook'lardan okunması
    /// (karar 45). Kapatılınca yönetilen girdiler sağlayıcı ayarlarından silinir
    /// ve durum yalnız OSC/çıktı sezgisiyle türer. Additive (karar 9): yoksa açık.
    public var agentHooksEnabled: Bool

    /// Terminal font boyutu için geçerli aralık — doğrulamanın TEK tanımı
    /// (refactor 5.7). `SettingsStore` clamp'i ve `SettingsView` slider'ı
    /// aynı sabitten türer; ikisi ayrı literal taşıdığında sessizce ayrışırdı.
    public static let terminalFontSizeRange = 10 ... 24

    /// Aralığa clamp'lenmiş font boyutu (doğrulama modelde, karar 9 sözleşmesi
    /// gibi tek yerde).
    public static func clampTerminalFontSize(_ size: Int) -> Int {
        min(max(size, terminalFontSizeRange.lowerBound), terminalFontSizeRange.upperBound)
    }

    public static let defaults = AppConfig(
        projectsRoot: "",
        additionalPaths: [],
        aiProvider: .claude,
        theme: "dark",
        terminalFontSize: 13,
        terminalFontFamily: "",
        terminalCursorStyle: TerminalCursorShape.block.rawValue,
        terminalCursorBlink: true,
        notifications: .defaults,
        autoMinimizeOnSend: false,
        sessionTrigger: .defaults,
        usageAutoRefresh: .defaults,
        usageIndicators: .defaults,
        computerAwakeMode: .default,
        agentHooksEnabled: true
    )

    public init(
        projectsRoot: String,
        additionalPaths: [AdditionalPath],
        aiProvider: AgentProvider,
        theme: String,
        terminalFontSize: Int,
        terminalFontFamily: String,
        terminalCursorStyle: String,
        terminalCursorBlink: Bool,
        notifications: NotificationSettings,
        autoMinimizeOnSend: Bool = false,
        sessionTrigger: SessionTrigger = .defaults,
        usageAutoRefresh: UsageAutoRefresh = .defaults,
        usageIndicators: UsageIndicators = .defaults,
        computerAwakeMode: ComputerAwakeMode = .default,
        agentHooksEnabled: Bool = true
    ) {
        self.projectsRoot = projectsRoot
        self.additionalPaths = additionalPaths
        self.aiProvider = aiProvider
        self.theme = theme
        self.terminalFontSize = terminalFontSize
        self.terminalFontFamily = terminalFontFamily
        self.terminalCursorStyle = terminalCursorStyle
        self.terminalCursorBlink = terminalCursorBlink
        self.notifications = notifications
        self.autoMinimizeOnSend = autoMinimizeOnSend
        self.sessionTrigger = sessionTrigger
        self.usageAutoRefresh = usageAutoRefresh
        self.usageIndicators = usageIndicators
        self.computerAwakeMode = computerAwakeMode
        self.agentHooksEnabled = agentHooksEnabled
    }
}
