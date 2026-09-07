import Foundation
import LumiKit

/// Tam fake servis grafiği (refactor 3.2). Bootstrap sırası sözleşmesi ve
/// composition kurulumu gerçek servis DOKUNMADAN test edilebilir.
///
/// Her alan `var`: test istediğini değiştirir (`registry.repo = ...`).
/// `paths` varsayılan olarak benzersiz bir temp dizinine bakar — `~/.lumi` ve
/// `~/.lumi-dev` hiçbir koşulda kirlenmez (karar 9).
@MainActor
public final class FakeServiceRegistry: ServiceRegistry {
    public var paths: LumiPaths
    public var config: any ConfigServicing
    public var system: any SystemServicing
    public var repo: any RepoServicing
    public var agentHistory: any AgentHistoryReading = FakeAgentHistoryService()
    public var git: any GitServicing
    public var plastic: any PlasticServicing = FakePlasticService()
    public var commitMessages: any CommitMessageGenerating = FakeCommitMessageGenerator()
    public var terminal: any TerminalServicing
    public var viewProvider: any TerminalViewProviding
    public var highlighter: any SyntaxHighlighting
    public var notifications: any NotificationServicing
    public var sessionStarter: any SessionStarterServicing
    public var activityMonitor: any ActivityMonitoring
    public var processSampler: any ProcessSampling
    public var sleepAssertion: any SleepAsserting
    public var agentHooks: any AgentHookServing
    public var agentHookInstaller: any AgentHookInstalling
    public var usageServices: [AgentProvider: any UsageServicing]

    /// Somut fake'lere tipli erişim (kayıt okumak için).
    public let fakeConfig: FakeConfigService
    public let fakeSystem: FakeSystemService
    public let fakeRepo: FakeRepoService
    public let fakeTerminal: FakeTerminalService
    public let fakeViewProvider: FakeTerminalViewProvider
    public let fakeNotifications: FakeNotificationService
    public let fakeProcessSampler: FakeProcessSampler
    public let fakeSleepAssertion: FakeSleepAssertion
    public let fakeAgentHooks: FakeAgentHookServer
    public let fakeAgentHookInstaller: FakeAgentHookInstaller

    public init(
        paths: LumiPaths = FakeServiceRegistry.temporaryPaths(),
        usageOutcome: FakeUsageService.Outcome = .failure(.usageUnavailable(detail: "fake"))
    ) {
        self.paths = paths
        let config = FakeConfigService()
        let system = FakeSystemService()
        let repo = FakeRepoService()
        let terminal = FakeTerminalService()
        let viewProvider = FakeTerminalViewProvider()
        let notifications = FakeNotificationService()
        fakeConfig = config
        fakeSystem = system
        fakeRepo = repo
        fakeTerminal = terminal
        fakeViewProvider = viewProvider
        fakeNotifications = notifications
        self.config = config
        self.system = system
        self.repo = repo
        self.git = FakeGitService()
        self.terminal = terminal
        self.viewProvider = viewProvider
        self.notifications = notifications
        self.highlighter = FakeSyntaxHighlighter()
        self.sessionStarter = FakeSessionStarterService()
        self.activityMonitor = FakeActivityMonitor(idleSeconds: 0)
        let sampler = FakeProcessSampler()
        let sleep = FakeSleepAssertion()
        fakeProcessSampler = sampler
        fakeSleepAssertion = sleep
        self.processSampler = sampler
        self.sleepAssertion = sleep
        let hooks = FakeAgentHookServer()
        let installer = FakeAgentHookInstaller()
        fakeAgentHooks = hooks
        fakeAgentHookInstaller = installer
        self.agentHooks = hooks
        self.agentHookInstaller = installer
        var usage: [AgentProvider: any UsageServicing] = [:]
        for provider in AgentProvider.allCases {
            usage[provider] = FakeUsageService(provider: provider, outcome: usageOutcome)
        }
        usageServices = usage
    }

    public func usage(for provider: AgentProvider) -> any UsageServicing {
        guard let service = usageServices[provider] else {
            preconditionFailure("kullanım servisi tanımsız: \(provider.rawValue)")
        }
        return service
    }

    /// Benzersiz temp kök — `ensureDirectoriesExist()` gerçek ev dizinine dokunmaz.
    public static func temporaryPaths() -> LumiPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-tests-\(UUID().uuidString)")
        return LumiPaths(
            mode: .development,
            homeDirectory: root,
            temporaryDirectory: root
        )
    }

    /// Testin kurduğu temp ağacını siler.
    public func removeTemporaryDirectories() {
        try? FileManager.default.removeItem(at: paths.configDir)
        try? FileManager.default.removeItem(at: paths.tempDir)
    }
}
