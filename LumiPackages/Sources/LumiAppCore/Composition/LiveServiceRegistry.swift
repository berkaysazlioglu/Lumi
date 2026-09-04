import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiTerminal

/// Üretim servis grafiği (refactor 3.2): eski `AppContainer.init` gövdesi.
/// Somut servis tipleri YALNIZ burada görünür; `AppContainer` ve feature
/// assembly'leri `ServiceRegistry` protokolünü görür.
@MainActor
final class LiveServiceRegistry: ServiceRegistry {
    let paths: LumiPaths
    let config: any ConfigServicing
    let system: any SystemServicing
    let repo: any RepoServicing
    let git: any GitServicing
    let terminal: any TerminalServicing
    let viewProvider: any TerminalViewProviding
    let notifications: any NotificationServicing
    let sessionStarter: any SessionStarterServicing
    let activityMonitor: any ActivityMonitoring

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
        }
        system = SystemService(
            checks: SystemService.defaultChecks(smokeTester: PTYSmokeTester()),
            pathFixer: PathEnvironmentFixer(),
            urlOpener: ExternalURLOpener(),
            fileOperations: FileSystemOperations(allowedRoots: allowedRoots),
            folderChooser: FolderChooser()
        )
        repo = RepoService()
        git = GitService()
        notifications = NotificationService(presenter: notificationPresenter)
        // K38-A: her kullanım kaynağı 5 dk TTL cache dekoratörüyle sarılır
        // (design/05 §cache "≥5 dk TTL"). En küçük otomatik tazeleme aralığı da
        // 5 dk olduğundan (`UsageAutoRefresh.allowedIntervals`) döngü cache'e
        // takılıp boşa dönmez; manuel yenileme cache'i açıkça geçersizler.
        usageServices = [
            .claude: Self.cached(ClaudeUsageService()),
            .codex: Self.cached(CodexUsageService()),
        ]
        activityMonitor = SystemActivityMonitor()
        sessionStarter = SessionStarterService()
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
