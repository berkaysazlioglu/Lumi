import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiTerminal
// Vurgulayıcının paleti/fontu tema token'larından gelir; composition root
// bunları servise enjekte eder (refactor 7.5) — servis LumiUI'ı görmez.
import LumiUI

/// Üretim servis grafiği (refactor 3.2): eski `AppContainer.init` gövdesi.
/// Somut servis tipleri YALNIZ burada görünür; `AppContainer` ve feature
/// assembly'leri `ServiceRegistry` protokolünü görür.
@MainActor
final class LiveServiceRegistry: ServiceRegistry {
    let paths: LumiPaths
    let config: any ConfigServicing
    let system: any SystemServicing
    let repo: any RepoServicing
    let workspaces: any WorkspaceServicing
    let agentHistory: any AgentHistoryServicing
    let agentSessionTransfer: any AgentSessionTransferring
    let deepSeek: any DeepSeekEnvironmentServicing
    let deepSeekBalance: any DeepSeekBalanceServicing
    let claudeAccounts: any ClaudeAccountServicing
    let codexAccounts: any CodexAccountServicing
    let git: any GitServicing
    let plastic: any PlasticServicing
    let commitMessages: any CommitMessageGenerating
    let quickCommandGenerator: any QuickCommandGenerating
    let terminal: any TerminalServicing
    let viewProvider: any TerminalViewProviding
    let highlighter: any SyntaxHighlighting
    let notifications: any NotificationServicing
    let sessionStarter: any SessionStarterServicing
    let activityMonitor: any ActivityMonitoring
    let processSampler: any ProcessSampling
    let sleepAssertion: any SleepAsserting
    let agentHooks: any AgentHookServing
    let agentHookInstaller: any AgentHookInstalling
    let chatSessions: any ChatSessionServicing

    private let usageServices: [AgentProvider: any UsageServicing]
    /// P1 ölçüm harness'ı somut manager'a bağlıdır (debug-only araç, design/04).
    /// Protokole sızdırmak yerine referansı burada saklanır.
    private let terminalManager: TerminalSessionManager

    /// `mode` artık `#if DEBUG` ile burada seçilmez — `AppBootstrap` verir
    /// (refactor 3.2: paths seçimi test edilebilir bir parametre).
    init(
        mode: LumiPaths.Mode,
        notificationPresenter: any NotificationPresenting = LogNotificationPresenter()
    ) {
        paths = LumiPaths(mode: mode)
        let configService = ConfigService(paths: paths)
        config = configService
        // Refactor 3.9: trash/reveal path guard'ının "bilinen kökler" kaynağı
        // config'tir (projectsRoot + additionalPaths). Liste boşsa
        // `FileSystemOperations` ev dizinine düşer.
        let allowedRoots: @Sendable () async -> [String] = {
            let current = await configService.config()
            return [current.projectsRoot] + current.additionalPaths.map(\.path)
                + current.workspaces.map(\.path)
        }
        system = SystemService(
            checks: SystemService.defaultChecks(smokeTester: PTYSmokeTester()),
            pathFixer: PathEnvironmentFixer(),
            urlOpener: ExternalURLOpener(),
            fileOperations: FileSystemOperations(allowedRoots: allowedRoots),
            folderChooser: FolderChooser()
        )
        repo = RepoService()
        workspaces = WorkspaceService()
        git = GitService()
        plastic = PlasticService()
        commitMessages = ClaudeCommitMessageService()
        quickCommandGenerator = ClaudeQuickCommandService()
        agentHistory = AgentHistoryService()
        agentSessionTransfer = AgentSessionTransferService()
        let deepSeekEnvironment = DeepSeekEnvironmentService()
        deepSeek = deepSeekEnvironment
        // Anahtar tek kaynaktan (env dosyası) okunur — servis onu saklamaz.
        deepSeekBalance = DeepSeekBalanceService(environment: deepSeekEnvironment)
        claudeAccounts = ClaudeAccountService(config: configService, paths: paths)
        let codexAccountService = CodexAccountService(config: configService, paths: paths)
        codexAccounts = codexAccountService
        highlighter = HighlightrEngine(style: HighlightrStyle(
            plainTextColor: Theme.NS.textPrimary,
            font: { LumiFonts.mono(size: $0) }
        ))
        notifications = NotificationService(presenter: notificationPresenter)
        // K38-A: her kullanım kaynağı 5 dk TTL cache dekoratörüyle sarılır
        // (design/05 §cache "≥5 dk TTL"). Otomatik döngü de manuel yenileme de
        // `UsageStore.refresh()`'ten geçip cache'i açıkça geçersizlediği için
        // 1 dk'lık aralık (karar 55) TTL'e takılmaz; TTL yalnız art arda gelen
        // KENDİLİĞİNDEN okumaları (ilk yükleme) sınırlar.
        usageServices = [
            .claude: Self.cached(ClaudeUsageService()),
            // Karar 55: Codex probe'u (süreç spawn'ı + RPC) asılabiliyordu;
            // 30 sn üst sınırı cache'in ALTINDA durur ki zaman aşımı
            // cache'lenmesin, bir sonraki yenileme yeniden denesin.
            .codex: Self.cached(TimeoutUsageService(wrapping: CodexUsageService(
                codexHome: { await codexAccountService.selectedHome() }
            ))),
        ]
        activityMonitor = SystemActivityMonitor()
        processSampler = PSProcessSampler()
        sleepAssertion = IOKitSleepAssertion()
        agentHooks = AgentHookServer()
        agentHookInstaller = AgentHookInstaller(paths: paths)
        sessionStarter = SessionStarterService()
        // Stream-json chat lane (Faz 2): child env'inden claude-oturum kimliği
        // temizlenir (AgentChildEnvironment) — nested-oturum transcript hatası.
        chatSessions = ChatSessionService(environment: AgentChildEnvironment.cleaned())
        let manager = TerminalSessionManager()
        terminalManager = manager
        terminal = manager
        viewProvider = manager.viewRegistry
    }

    /// Kullanım göstergesi TTL'i — design/05 §cache.
    static let usageCacheTTL: Duration = .seconds(300)

    private static func cached(_ service: any UsageServicing) -> any UsageServicing {
        CachingUsageService(wrapping: service, ttl: usageCacheTTL)
    }

    func usage(for provider: AgentProvider) -> any UsageServicing {
        // Tablo `AgentProvider.allCases` ile doldurulur; eksik anahtar
        // programlama hatasıdır (yeni sağlayıcı eklenip servisi unutulmuş).
        guard let service = usageServices[provider] else {
            preconditionFailure("kullanım servisi tanımsız: \(provider.rawValue)")
        }
        return service
    }

    /// P1 harness'ı (`--p1`) somut manager'ı ister; debug ölçüm aracı olduğu
    /// için fabrikası registry'de durur.
    func makeP1Harness(store: TerminalListStore) -> P1Harness {
        P1Harness(manager: terminalManager, store: store)
    }
}
