import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiTerminal

/// Composition root (design/00 §3). Tüm servisler ve store'lar burada, protokol
/// tipleriyle BİR KEZ inşa edilir; somut tipleri yalnız bu hedef tanır.
/// Gerçek app target'a taşınana dek skeleton'da yaşar.
@MainActor
final class AppContainer {
    let paths: LumiPaths
    let config: any ConfigServicing
    let system: any SystemServicing
    let repoService: any RepoServicing
    let notifications: any NotificationServicing
    let terminal: TerminalSessionManager
    let toasts: ToastStore
    let terminals: TerminalListStore
    let repoStore: RepoStore
    let workspace: WorkspaceStore
    let configCoordinator: ConfigSideEffectCoordinator

    private var bridgeTasks: [Task<Void, Never>] = []

    init() {
        #if DEBUG
        let mode = LumiPaths.Mode.development
        #else
        let mode = LumiPaths.Mode.production
        #endif
        paths = LumiPaths(mode: mode)
        config = ConfigService(paths: paths)
        system = SystemService(smokeTester: PTYSmokeTester())
        repoService = RepoService()
        notifications = NotificationService(presenter: LogNotificationPresenter())
        terminal = TerminalSessionManager()
        toasts = ToastStore()
        terminals = TerminalListStore(service: terminal, toasts: toasts)
        repoStore = RepoStore(service: repoService)
        workspace = WorkspaceStore(config: config, terminals: terminals)
        configCoordinator = ConfigSideEffectCoordinator(
            config: config,
            terminal: terminal,
            repo: repoService,
            repoStore: repoStore,
            notifications: notifications
        )
    }

    /// Sıra-bağımlı bootstrap (design/00 §3 + spec/21 §13): dizinler →
    /// fixProcessPath (spawn'dan ÖNCE) → config'in anlık değerleri → repo'lar →
    /// ui-state (migration repo listesini okur) → store/koordinatör/köprüler.
    func start() async {
        do {
            try paths.ensureDirectoriesExist()
        } catch {
            toasts.show(error: .configIOFailed(
                file: paths.configDir.path,
                detail: error.localizedDescription
            ))
        }

        await system.fixProcessPath()

        let appConfig = await config.config()
        terminal.setMaxTerminals(appConfig.maxTerminals)
        notifications.updateSettings(appConfig.notifications)
        repoStore.additionalPaths = appConfig.additionalPaths
        await repoService.setRoots(
            projectsRoot: appConfig.projectsRoot,
            additionalPaths: appConfig.additionalPaths
        )

        terminals.start()
        repoStore.start()
        await repoStore.reload()
        await workspace.load(repos: repoStore.repos)

        configCoordinator.start()
        startBridges()

        terminal.onTerminalViewFocused = { [weak self] id in
            self?.terminals.focus(id)
        }
    }

    private func startBridges() {
        // Terminal status event'leri → NotificationService (spec/10 §5 onChange köprüsü)
        let terminalStream = terminal.events()
        bridgeTasks.append(Task { @MainActor [weak self] in
            for await event in terminalStream {
                guard let self else { return }
                switch event {
                case .statusChanged(let id, let status):
                    let repoName = self.terminals.meta(for: id)
                        .map { ($0.repoPath as NSString).lastPathComponent } ?? "Terminal"
                    self.notifications.handleStatusChange(id: id, repoName: repoName, status: status)
                case .exited(let id, _):
                    // Cleanup sözleşmesi: interval timer'lar iptal edilir (sızıntı yok)
                    self.notifications.terminalRemoved(id)
                case .spawned, .titleChanged, .bell:
                    break
                }
            }
        })

        // Bildirim event'leri → store'lar
        let notificationStream = notifications.events()
        bridgeTasks.append(Task { @MainActor [weak self] in
            for await event in notificationStream {
                guard let self else { return }
                switch event {
                case .clicked(let id):
                    // Minimize istisnası: bildirim tıklaması restore + focus (spec/21 §6)
                    self.terminals.restoreAndFocus(id)
                case .bell(let id, let repoName):
                    self.toasts.show(
                        .bell,
                        title: repoName,
                        message: NotificationService.waitingBody,
                        terminalID: id
                    )
                }
            }
        })
    }

    func defaultRepoPath() async -> String {
        let appConfig = await config.config()
        return appConfig.projectsRoot.isEmpty ? NSHomeDirectory() : appConfig.projectsRoot
    }

    func shutdown() async {
        bridgeTasks.forEach { $0.cancel() }
        terminal.killAll()
        await config.flushPendingWrites()
    }
}
