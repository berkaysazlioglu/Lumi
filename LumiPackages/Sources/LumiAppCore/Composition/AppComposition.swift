import Foundation
import LumiKit
import LumiState

/// Üretim kompozisyonu: servis grafiği + paylaşılan store'lar + feature
/// assembly'leri (refactor 3.3 / K36).
///
/// `AppContainer` feature tanımaz; AppKit kabuğunun (menü aksiyonları, quit
/// akışı) somut store'lara ihtiyacı olduğu için tipli erişim BURADA durur.
/// Kabuğun kendisi artık tek bir `ShellComposition` üzerinden kurulur
/// (Faz 6.6): registry + `ShellContext`.
@MainActor
struct AppComposition {
    let registry: LiveServiceRegistry
    let container: AppContainer
    let shared: SharedStores
    /// AppKit kabuğunun (uyanma sonrası tazeleme) hâlâ tipli eriştiği tek
    /// assembly. Faz 6.1 sonrası diğerleri yalnız `ShellComposition`'a girer.
    let repo: RepoFeatureAssembly
    /// Remote terminal-mirror assembly (Task 5); Task 6'da ShellContext'e verilecek.
    let remote: RemoteFeatureAssembly
    /// Panel/route/overlay kayıt defteri + kabuk bağlamı (Faz 6.6).
    let shell: ShellComposition

    /// Yeni özellik = yeni assembly + BU listeye bir satır.
    static func live(
        mode: LumiPaths.Mode,
        notificationPresenter: any NotificationPresenting
    ) -> AppComposition {
        let registry = LiveServiceRegistry(
            mode: mode,
            notificationPresenter: notificationPresenter
        )
        let shared = SharedStores.make(
            config: registry.config,
            terminal: registry.terminal,
            viewProvider: registry.viewProvider
        )
        let agentHooks = AgentHooksAssembly()
        let terminal = TerminalFeatureAssembly()
        let notifications = NotificationAssembly()
        let sessionSchedule = SessionScheduleAssembly()
        let usage = UsageFeatureAssembly()
        let repo = RepoFeatureAssembly()
        let workspaceBoot = WorkspaceBootAssembly()
        let statusBar = StatusBarFeatureAssembly()
        let remote = RemoteFeatureAssembly()
        let deepSeek = DeepSeekAssembly()
        let tasks = TasksFeatureAssembly()
        // Hesap değişince Claude göstergesi yeni hesabın kotasını göstermeli.
        let claudeAccounts = ClaudeAccountsAssembly(refreshClaudeUsage: { [weak usage] in
            guard let store = usage?.usageStores[.claude] else { return }
            Task { await store.refreshAfterSourceChange() }
        })
        let codexAccounts = CodexAccountsAssembly(refreshCodexUsage: { [weak usage] in
            guard let store = usage?.usageStores[.codex] else { return }
            Task { await store.refreshAfterSourceChange() }
        })
        let terminalLinks = TerminalLinkActionsAssembly()
        let appUpdate = AppUpdateFeatureAssembly()
        let orchestrator = OrchestratorFeatureAssembly()
        let container = AppContainer(
            services: registry,
            shared: shared,
            assemblies: [
                agentHooks, terminal, notifications, sessionSchedule, usage, repo, codexAccounts,
                workspaceBoot, statusBar, remote, deepSeek, tasks, claudeAccounts, terminalLinks,
                appUpdate, orchestrator,
            ]
        )
        let shell = ShellComposition.make(
            registry: registry,
            shared: shared,
            repo: repo,
            terminal: terminal,
            usage: usage,
            sessionSchedule: sessionSchedule,
            workspaceBoot: workspaceBoot,
            statusBar: statusBar,
            remote: remote,
            deepSeek: deepSeek,
            claudeAccounts: claudeAccounts,
            codexAccounts: codexAccounts,
            terminalLinks: terminalLinks,
            appUpdate: appUpdate,
            orchestrator: orchestrator,
            contributors: [
                tasks, terminal, repo, usage, statusBar, claudeAccounts, codexAccounts, terminalLinks,
                orchestrator,
            ]
        )
        return AppComposition(
            registry: registry,
            container: container,
            shared: shared,
            repo: repo,
            remote: remote,
            shell: shell
        )
    }
}
