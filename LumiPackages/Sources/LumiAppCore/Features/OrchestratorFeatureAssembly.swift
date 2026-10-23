import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiUI
import SwiftUI

/// Orchestrator (karar 114/123/124): tüm ajan terminallerini yöneten,
/// etkileşimli bir Codex terminali.
///
/// Top bar butonu, docked panel (`.innerRight`) ve %80'lik popup kabuğa
/// buradan kaydedilir; araçlar Lumi'nin loopback MCP sunucusundan
/// `OrchestratorToolbox`'a düşer. Codex panel ya da popup ilk açıldığında
/// başlar; daha önce kullanıldıysa uygulama açılışında arka planda
/// sürdürülür ki monitoring hiçbir yüzey açılmadan da işlesin. Quit'te
/// sonlandırılır (konuşma Codex thread'inde kalır).
@MainActor
final class OrchestratorFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.ui

    private(set) var orchestrator: OrchestratorStore!
    /// Faz 4: bitiş/soru özetleri Activity paneline.
    private var digests: TerminalDigestCoordinator!
    /// Karar 123 Faz 2: yeni özetleri `codex queue` ile orchestrator'a bırakır.
    private var monitor: OrchestratorActivityMonitor!
    /// Raporu gelen, izlenen terminaller — açılışta diskten geri bağlanır.
    private var watchList: OrchestratorWatchList!
    private var terminals: TerminalListStore!
    /// Araçlar Projects ağacını okur — repo/workspace store'ları repo
    /// assembly'sinde doğar (`.repo` fazı `.ui`'dan önce kurulur).
    private let repo: RepoFeatureAssembly
    /// `send_to_terminal` meşgul ajana prompt kuyruğundan gider (`.system` fazı).
    private let terminal: TerminalFeatureAssembly

    init(repo: RepoFeatureAssembly, terminal: TerminalFeatureAssembly) {
        self.repo = repo
        self.terminal = terminal
    }

    func build(services: any ServiceRegistry, shared: SharedStores) {
        let terminalService = services.terminal
        let watchList = OrchestratorWatchList(config: services.config)
        self.watchList = watchList
        terminals = shared.terminals
        // Karar 126: araç çağrıları ve teslim edilen özetler ışık süzmesi kaldırır.
        let flights = OrchestratorFlights()
        let toolbox = OrchestratorToolbox(
            terminals: shared.terminals,
            workspaces: repo.workspaceStore,
            repos: repo.repoStore,
            transcripts: services.terminalTranscripts,
            screenText: { id in String(decoding: terminalService.serializeScrollback(id).data, as: UTF8.self) },
            promptQueue: terminal.promptQueue,
            trust: ClaudeWorkspaceTrust(),
            watchList: watchList,
            summarizer: services.terminalDigests,
            flights: flights
        )
        let activity = OrchestratorActivityFeed()
        let codexAccounts = services.codexAccounts
        orchestrator = OrchestratorStore(
            terminal: services.orchestratorTerminal,
            viewProvider: services.orchestratorViewProvider,
            launcher: services.orchestratorLauncher,
            config: services.config,
            workingDirectory: services.paths.orchestratorDir.path,
            control: services.orchestratorControl,
            tools: toolbox,
            activity: activity,
            watchList: watchList,
            flights: flights,
            // Karar 123: talimat her açılışta canlı Projects ağacından üretilir.
            promptContext: { (toolbox.promptProjects(), toolbox.promptWatchedTerminals()) },
            // Karar 78: seçili Codex hesabı orchestrator'a da uygulanır.
            codexHome: { await codexAccounts.selectedHome() }
        )
        let store: OrchestratorStore = orchestrator
        monitor = OrchestratorActivityMonitor(
            feed: activity,
            launcher: services.orchestratorLauncher,
            target: { store.deliveryTarget }
        )
        orchestrator.onDeliveryTargetAvailable = { [weak monitor] in monitor?.targetBecameAvailable() }
        monitor.onDelivered = { events in flights.launch(.inbound, events.map { .terminal($0.terminalID) }) }
        let config = services.config
        digests = TerminalDigestCoordinator(
            service: terminalService,
            terminals: shared.terminals,
            toolbox: toolbox,
            summarizer: services.terminalDigests,
            feed: activity,
            watchList: watchList,
            // Yalnız izlenen terminaller raporlanır; izleme orchestrator'dan
            // doğduğu için hiç kullanmayan kullanıcıda haiku çağrısı yapılmaz.
            isEnabled: { await config.config().orchestratorDigestsEnabled }
        )
    }

    func registerShellItems(into registries: ShellRegistries) {
        // Karar 124: varsayılan sunum orta alan ile sağ panel arasındaki panel;
        // repo'ya bağlı değildir (All Terminals'ta ve proje yokken de açılır).
        registries.panels.register(PanelItemDescriptor(
            id: .orchestrator,
            title: "Orchestrator",
            icon: OrchestratorToolbarItem.iconName,
            defaultSlot: .innerRight,
            makeView: { AnyView(OrchestratorPanel()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .orchestrator,
            isPresented: { $0.dialogs.isOrchestratorOpen },
            makeView: { AnyView(OrchestratorOverlay()) }
        ))
        // Karar 126: popup'ın üstünde, kabuğun Settings / dialog overlay'lerinin
        // altında (feature overlay'leri kabuğunkilerden önce kaydedilir).
        registries.overlays.register(OverlayDescriptor(
            id: .orchestratorFlights,
            isPresented: { !$0.orchestrator.flights.active.isEmpty },
            makeView: { AnyView(OrchestratorFlightOverlay()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .orchestrator,
            region: .trailing,
            order: ShellToolbarItems.Order.orchestrator,
            makeView: { AnyView(OrchestratorToolbarItem()) }
        ))
    }

    func start() async {
        orchestrator.start()
        monitor.start()
        digests.start()
        await watchList.load(matching: terminals.terminals)
        // İzleme listesi yüklendikten SONRA: talimat izlenen terminalleri görsün.
        // Bootstrap'ı bekletmez (açılış `codex mcp list`'i bekleyebilir).
        let store: OrchestratorStore = orchestrator
        Task { await store.resumeIfUsedBefore() }
    }

    func shutdown() async {
        digests.stop()
        monitor.stop()
        await orchestrator.shutdown()
        await watchList.flush()
    }
}
