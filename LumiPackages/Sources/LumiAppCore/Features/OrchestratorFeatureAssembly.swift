import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiUI
import SwiftUI

/// Orchestrator (karar 103): tüm ajan terminallerini yöneten sohbet.
///
/// Top bar butonu + %80'lik popup kabuğa buradan kaydedilir; araçlar (Faz 2)
/// Lumi'nin loopback MCP sunucusundan `OrchestratorToolbox`'a düşer. Süreç
/// açılışta BAŞLAMAZ — popup ilk açıldığında ya da ilk mesajda tembel başlar;
/// quit'te sonlandırılır (konuşma transkriptte kalır, sonraki açılış resume eder).
@MainActor
final class OrchestratorFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.ui

    private(set) var orchestrator: OrchestratorStore!
    /// Faz 4: bitiş/soru özetleri Activity paneline.
    private var digests: TerminalDigestCoordinator!
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
        let approvals = OrchestratorApprovals()
        let toolbox = OrchestratorToolbox(
            terminals: shared.terminals,
            workspaces: repo.workspaceStore,
            repos: repo.repoStore,
            transcripts: services.terminalTranscripts,
            screenText: { id in String(decoding: terminalService.serializeScrollback(id).data, as: UTF8.self) },
            approvals: approvals,
            promptQueue: terminal.promptQueue,
            trust: ClaudeWorkspaceTrust()
        )
        let activity = OrchestratorActivityFeed()
        orchestrator = OrchestratorStore(
            service: services.orchestrator,
            config: services.config,
            control: services.orchestratorControl,
            tools: toolbox,
            approvals: approvals,
            activity: activity
        )
        let config = services.config
        digests = TerminalDigestCoordinator(
            service: terminalService,
            terminals: shared.terminals,
            toolbox: toolbox,
            summarizer: services.terminalDigests,
            feed: activity,
            // Ayar açık VE orchestrator en az bir kez kullanılmış olmalı —
            // hiç açmayan kullanıcı için haiku çağrısı yapılmaz.
            isEnabled: {
                guard await config.config().orchestratorDigestsEnabled else { return false }
                return await config.uiState().orchestratorSessionID != nil
            }
        )
    }

    func registerShellItems(into registries: ShellRegistries) {
        registries.overlays.register(OverlayDescriptor(
            id: .orchestrator,
            isPresented: { $0.dialogs.isOrchestratorOpen },
            makeView: { AnyView(OrchestratorOverlay()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .orchestrator,
            region: .trailing,
            order: ShellToolbarItems.Order.orchestrator,
            makeView: { AnyView(OrchestratorToolbarItem()) }
        ))
    }

    func start() async {
        digests.start()
    }

    func shutdown() async {
        digests.stop()
        await orchestrator.shutdown()
    }
}
