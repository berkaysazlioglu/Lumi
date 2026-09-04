import Foundation
import LumiKit
import LumiState

/// Üretim kompozisyonu: servis grafiği + paylaşılan store'lar + feature
/// assembly'leri (refactor 3.3 / K36).
///
/// `AppContainer` feature tanımaz; AppKit kabuğunun (RootView kurulumu, menü
/// aksiyonları) somut store'lara ihtiyacı olduğu için tipli erişim BURADA
/// durur. Faz 6'da `RootView` `ShellContext`'e geçince bu tipli alanların
/// çoğu kaybolacak.
@MainActor
struct AppComposition {
    let registry: LiveServiceRegistry
    let container: AppContainer
    let shared: SharedStores
    let terminal: TerminalFeatureAssembly
    let repo: RepoFeatureAssembly
    let usage: UsageFeatureAssembly
    let sessionSchedule: SessionScheduleAssembly
    let notifications: NotificationAssembly
    let workspaceBoot: WorkspaceBootAssembly

    /// Yeni özellik = yeni assembly + BU listeye bir satır.
    static func live(
        mode: LumiPaths.Mode,
        notificationPresenter: any NotificationPresenting
    ) -> AppComposition {
        let registry = LiveServiceRegistry(
            mode: mode,
            notificationPresenter: notificationPresenter
        )
        let shared = SharedStores.make(config: registry.config, terminal: registry.terminal)
        let terminal = TerminalFeatureAssembly()
        let notifications = NotificationAssembly()
        let sessionSchedule = SessionScheduleAssembly()
        let usage = UsageFeatureAssembly()
        let repo = RepoFeatureAssembly()
        let workspaceBoot = WorkspaceBootAssembly()
        let container = AppContainer(
            services: registry,
            shared: shared,
            assemblies: [terminal, notifications, sessionSchedule, usage, repo, workspaceBoot]
        )
        return AppComposition(
            registry: registry,
            container: container,
            shared: shared,
            terminal: terminal,
            repo: repo,
            usage: usage,
            sessionSchedule: sessionSchedule,
            notifications: notifications,
            workspaceBoot: workspaceBoot
        )
    }
}
