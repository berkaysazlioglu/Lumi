import Foundation

/// Servis grafiğinin tek erişim yüzü (refactor 3.2, design/00 §3).
///
/// Composition root somut tipleri yalnız `LiveServiceRegistry` içinde tanır;
/// `AppContainer` ve feature assembly'leri bu protokolü görür. Böylece bootstrap
/// sırası sözleşmesi tamamen fake bir grafikle test edilebilir
/// (`FakeServiceRegistry`) ve `LumiPaths.Mode` seçimi `#if DEBUG`'dan çıkıp
/// executable'ın girişine (`AppBootstrap`) taşınır.
@MainActor
public protocol ServiceRegistry: AnyObject {
    /// `~/.lumi` (prod) veya `~/.lumi-dev` (dev) çözümlemesi — karar 9.
    var paths: LumiPaths { get }

    var config: any ConfigServicing { get }
    var system: any SystemServicing { get }
    var repo: any RepoServicing { get }
    var workspaces: any WorkspaceServicing { get }
    var git: any GitServicing { get }
    /// Plastic SCM yüzeyi (karar 46): okuma + checkin/undo.
    var plastic: any PlasticServicing { get }
    /// Commit/checkin mesajı üreticisi (karar 47) — `claude -p` arka planda.
    var commitMessages: any CommitMessageGenerating { get }
    /// Hızlı komut üreticisi (karar 92) — araçlı `claude -p`.
    var quickCommandGenerator: any QuickCommandGenerating { get }
    /// Çalıştırılacak hızlı komut script'lerinin yazıcısı (karar 92).
    var quickCommandScripts: any QuickCommandScriptWriting { get }
    /// `Start App`'in terminalsiz başlatıcısı (karar 93).
    var quickCommandLauncher: any QuickCommandBackgroundLaunching { get }
    var agentHistory: any AgentHistoryServicing { get }
    /// Agent History oturumu dışa/içe aktarımı (karar 52).
    var agentSessionTransfer: any AgentSessionTransferring { get }
    /// DeepSeek env dosyası kurulumu (karar 54).
    var deepSeek: any DeepSeekEnvironmentServicing { get }
    /// DeepSeek bakiye okuması (karar 75).
    var deepSeekBalance: any DeepSeekBalanceServicing { get }
    /// Claude hesap yönetimi (karar 56).
    var claudeAccounts: any ClaudeAccountServicing { get }
    /// Codex accounts stored as isolated CODEX_HOME directories.
    var codexAccounts: any CodexAccountServicing { get }

    /// Oturum kontrolü + görünüm ayarı (ISP: `TerminalServicing` bileşimi).
    /// Somut `TerminalSessionManager` bu yüzeyin ARDINDA kalır.
    var terminal: any TerminalServicing { get }
    /// Canlı NSView köprüsü ayrı bir yüzdür (design/00 §2 sınır hilesi);
    /// terminal servisinin bir alanı olarak sızdırılmaz.
    var viewProvider: any TerminalViewProviding { get }

    /// FileViewer'ın sözdizimi vurgulayıcısı (refactor 7.5). Somut motor
    /// (`HighlightrEngine`, JSCore) LumiServices'te; kabuk yalnız protokolü görür.
    var highlighter: any SyntaxHighlighting { get }

    var notifications: any NotificationServicing { get }
    var sessionStarter: any SessionStarterServicing { get }
    var activityMonitor: any ActivityMonitoring { get }
    /// Karar 43: alt bar Resource Manager örnekleyicisi ve uyku engeli.
    var processSampler: any ProcessSampling { get }
    var sleepAssertion: any SleepAsserting { get }
    /// Karar 45: ajan hook sunucusu ve sağlayıcı ayar dosyalarına kurulumu.
    var agentHooks: any AgentHookServing { get }
    var agentHookInstaller: any AgentHookInstalling { get }

    /// Stream-json chat lane oturum yöneticisi (Yol B Faz 2). Chat oturumları
    /// PTY'siz `claude --output-format stream-json` child'larıdır.
    var chatSessions: any ChatSessionServicing { get }

    /// Sağlayıcı başına kullanım servisi (karar 32). Sözlük yerine fonksiyon:
    /// yeni sağlayıcı eklendiğinde çağıranlar `nil` ele almak zorunda kalmaz.
    func usage(for provider: AgentProvider) -> any UsageServicing
}
