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
    /// Karar 115: Git worktree'lerinin canlı keşfi + dizin izleyicileri.
    var worktrees: any WorktreeDiscovering { get }
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
    /// Oturum sunucusu istemcisi (karar 138, Lumi Sessions Protocol v1).
    var sessionSharing: any SessionSharingMaking { get }
    /// Oturum sunucusu token'ı (Keychain `com.lumi.sessions`).
    var sessionServerCredentials: any SessionServerCredentialStoring { get }
    /// DeepSeek env dosyası kurulumu (karar 54).
    var deepSeek: any DeepSeekEnvironmentServicing { get }
    /// DeepSeek bakiye okuması (karar 75).
    var deepSeekBalance: any DeepSeekBalanceServicing { get }
    /// GitHub Releases'ten son sürüm kontrolü (karar 102).
    var appReleases: any AppReleaseChecking { get }
    /// Yeni sürümü indirip Lumi kapanınca kuran servis (karar 118).
    var appUpdateInstaller: any AppUpdateInstalling { get }
    /// Claude hesap yönetimi (karar 56).
    var claudeAccounts: any ClaudeAccountServicing { get }
    /// Codex accounts stored as isolated CODEX_HOME directories.
    var codexAccounts: any CodexAccountServicing { get }
    /// Tasks planı: bağlı task kaynağı → adapter.
    var taskProviders: any TaskProviderMaking { get }
    /// Task görsellerinin indirme/önbelleği.
    var taskImages: any TaskImageLoading { get }
    /// Task kaynağı token'ları (Keychain).
    var taskCredentials: any TaskCredentialStoring { get }
    /// Task ajanlarının MCP sunucusu (`get_task`, `submit_for_review`).
    var taskAgentTools: any TaskAgentToolServing { get }

    /// Oturum kontrolü + görünüm ayarı (ISP: `TerminalServicing` bileşimi).
    /// Somut `TerminalSessionManager` bu yüzeyin ARDINDA kalır.
    var terminal: any TerminalServicing { get }
    /// Canlı NSView köprüsü ayrı bir yüzdür (design/00 §2 sınır hilesi);
    /// terminal servisinin bir alanı olarak sızdırılmaz.
    var viewProvider: any TerminalViewProviding { get }

    /// FileViewer'ın sözdizimi vurgulayıcısı (refactor 7.5). Somut motor
    /// (`HighlightJSEngine`, JSCore) LumiServices'te; kabuk yalnız protokolü görür.
    var highlighter: any SyntaxHighlighting { get }
    /// Karar 109: FileViewer'ın render'lı markdown ayrıştırıcısı (cmark-gfm,
    /// LumiServices'te); kabuk yalnız saf `MarkdownDocument` modelini görür.
    var markdownParser: any MarkdownParsing { get }

    var notifications: any NotificationServicing { get }
    var sessionStarter: any SessionStarterServicing { get }
    var activityMonitor: any ActivityMonitoring { get }
    /// Karar 43: alt bar Resource Manager örnekleyicisi ve uyku engeli.
    var processSampler: any ProcessSampling { get }
    var sleepAssertion: any SleepAsserting { get }
    /// Karar 122: kapak kapalıyken uyku engeli (`pmset disablesleep`).
    var lidSleep: any LidSleepControlling { get }
    /// Karar 45: ajan hook sunucusu ve sağlayıcı ayar dosyalarına kurulumu.
    var agentHooks: any AgentHookServing { get }
    var agentHookInstaller: any AgentHookInstalling { get }

    /// Stream-json chat lane oturum yöneticisi (Yol B Faz 2). Chat oturumları
    /// PTY'siz `claude --output-format stream-json` child'larıdır.
    var chatSessions: any ChatSessionServicing { get }

    /// Karar 123: orchestrator Codex'inin kendi terminal yöneticisi — ana
    /// servisten ayrıdır ki terminali grid'e, Projects'e, telefona ve resume
    /// listesine hiç girmesin.
    var orchestratorTerminal: any TerminalServicing { get }
    var orchestratorViewProvider: any TerminalViewProviding { get }
    /// Karar 123: Codex açılış komutu + `codex queue`.
    var orchestratorLauncher: any OrchestratorLaunching { get }
    /// Karar 114 Faz 2: orchestrator'ın Lumi'yi yönettiği loopback MCP sunucusu.
    var orchestratorControl: any OrchestratorControlServing { get }
    /// Claude terminallerinin transkript kuyruğu (`read_terminal`).
    var terminalTranscripts: any TerminalTranscriptReading { get }
    /// Faz 4: uzun ajan mesajlarının haiku özeti.
    var terminalDigests: any TerminalDigestSummarizing { get }

    /// Sağlayıcı başına kullanım servisi (karar 32). Sözlük yerine fonksiyon:
    /// yeni sağlayıcı eklendiğinde çağıranlar `nil` ele almak zorunda kalmaz.
    func usage(for provider: AgentProvider) -> any UsageServicing
}
