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
        let container = AppContainer(
            services: registry,
            shared: shared,
            assemblies: [agentHooks, terminal, notifications, sessionSchedule, usage, repo, workspaceBoot, statusBar]
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
            contributors: [terminal, repo, usage, statusBar]
        )
        return AppComposition(
            registry: registry,
            container: container,
            shared: shared,
            repo: repo,
            shell: shell
        )
    }
}
