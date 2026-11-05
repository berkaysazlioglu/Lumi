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
    /// Mac'ten Mac'e remote'un controller tarafı (docs/design/08).
    private(set) var controllerStore: RemoteControllerStore!
    private var remoteService: RemoteService!
    private var controllerService: RemoteControllerService!
    private var configTask: Task<Void, Never>?
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
            hubSecrets: RemoteHubSecrets(keychain: services.remoteKeychain),
            chatSource: TranscriptChatSource(),
            trust: ClaudeWorkspaceTrust(),
            hookEvents: { services.agentHooks.events() },
            transcriptLocator: TranscriptLocator(),
            chatSessions: services.chatSessions,
            workspaces: services.workspaces,
            config: services.config
        )
        remoteStore = RemoteStore(service: remoteService)
        controllerService = RemoteControllerService(keychain: services.remoteKeychain)
        controllerStore = RemoteControllerStore(service: controllerService)
    }

    func start() async {
        // store event köprüsü (senkron); servis bağlantısı ayrı Task'ta (bloke etmez).
        // config.enabled=false ise start() içi no-op.
        remoteStore.start()
        controllerStore.start()
        // Controller ağ token'ını / relay adresini RemoteService'in config'inden alır;
        // config her değiştiğinde (ve ilk açılışta, hubId üretilince) yeniden kurulur.
        let configStream = remoteService.events()
        configTask = Task { [weak self] in
            for await event in configStream {
                if case .configChanged = event { self?.configureController() }
            }
        }
        Task { [remoteService] in await remoteService?.start() }
        let service = remoteService!
        usageBridge.start { report in await service.publishUsage(report) }
    }

    /// Telefondaki Tasks köprüsü (karar 137 mobil ek) buradan bağlanır.
    var service: RemoteService { remoteService }

    func shutdown() async {
        usageBridge.stop()
        configTask?.cancel()
        controllerStore.stop()
        remoteService.stop()
    }

    private func configureController() {
        let config = remoteService.currentConfig
        controllerStore.configure(
            relayUrl: config.relayUrl,
            networkToken: config.networkToken,
            identity: RemoteControllerIdentity(
                controllerId: config.hubId,
                name: remoteService.effectiveHubName,
                ownHubId: config.hubId))
    }
}
