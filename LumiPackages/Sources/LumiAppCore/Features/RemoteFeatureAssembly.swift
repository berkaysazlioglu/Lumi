import Foundation
import LumiKit
import LumiRemote
import LumiServices
import LumiState

/// Remote (terminal-ayna) özelliği: RemoteService + RemoteStore kurar, config
/// etkinse relay'e bağlanır. bootstrapPhase.config — terminal (system) kurulduktan
/// sonra başlaması yeterli.
///
/// Bağlantı ayrı Task'a alınır (eski AppContainer'ın `Task { await remoteService.start() }`
/// deseni): relay el sıkışması / ulaşılamayan relay bootstrap loop'unu bloke etmez.
@MainActor
final class RemoteFeatureAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.config

    private(set) var remoteStore: RemoteStore!
    private var remoteService: RemoteService!
    private var services: (any ServiceRegistry)!
    /// Kota göstergeleri → telefon (karar 128).
    private let usageBridge: RemoteUsageBridge

    init(usage: UsageFeatureAssembly) {
        usageBridge = RemoteUsageBridge(usage: usage)
    }

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        remoteService = RemoteService(
            paths: services.paths,
            terminal: services.terminal,
            repos: services.repo,
            chatSource: TranscriptChatSource(),
            trust: ClaudeWorkspaceTrust(),
            hookEvents: { services.agentHooks.events() },
            transcriptLocator: TranscriptLocator(),
            chatSessions: services.chatSessions,
            workspaces: services.workspaces,
            config: services.config
        )
        remoteStore = RemoteStore(service: remoteService)
    }

    func start() async {
        // store event köprüsü (senkron); servis bağlantısı ayrı Task'ta (bloke etmez).
        // config.enabled=false ise start() içi no-op.
        remoteStore.start()
        Task { [remoteService] in await remoteService?.start() }
        let service = remoteService!
        usageBridge.start { report in await service.publishUsage(report) }
    }

    func shutdown() async {
        usageBridge.stop()
        remoteService.stop()
    }
}
