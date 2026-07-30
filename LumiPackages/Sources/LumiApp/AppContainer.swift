import Foundation
import LumiKit
import LumiRemote
import LumiServices
import LumiState
import LumiTerminal
import LumiUI

/// Composition root (design/00 §3). Tüm servisler ve store'lar burada, protokol
/// tipleriyle BİR KEZ inşa edilir; somut tipleri yalnız bu hedef tanır.
@MainActor
final class AppContainer {
    let paths: LumiPaths
    let config: any ConfigServicing
    let system: any SystemServicing
    let repoService: any RepoServicing
    let gitService: any GitServicing
    let personaService: any PersonaServicing
    let actionService: any ActionServicing
    let notifications: any NotificationServicing
    let usageService: any UsageServicing
    let activityMonitor: any ActivityMonitoring
    let sessionStarter: any SessionStarterServicing
    let terminal: TerminalSessionManager
    let toasts: ToastStore
    let terminals: TerminalListStore
    let promptQueue: PromptQueueStore
    let sessionSchedule: SessionScheduleStore
    let repoStore: RepoStore
    let gitStore: GitStore
    let fileViewer: FileViewerStore
    let personasStore: PersonasStore
    let actionsStore: ActionsStore
    let settings: SettingsStore
    let usageStore: UsageStore
    let usageAutoRefresh: UsageAutoRefreshStore
    let remoteDashboardServer: any RemoteDashboardServing
    let remoteDashboard: RemoteDashboardStore
    let workspace: WorkspaceStore
    let configCoordinator: ConfigSideEffectCoordinator

    private var bridgeTasks: [Task<Void, Never>] = []

    init(notificationPresenter: any NotificationPresenting = LogNotificationPresenter()) {
        #if DEBUG
        let mode = LumiPaths.Mode.development
        #else
        let mode = LumiPaths.Mode.production
        #endif
        paths = LumiPaths(mode: mode)
        config = ConfigService(paths: paths)
        system = SystemService(smokeTester: PTYSmokeTester())
        repoService = RepoService()
        gitService = GitService()
        notifications = NotificationService(presenter: notificationPresenter)
        usageService = UsageService()
        activityMonitor = SystemActivityMonitor()
        sessionStarter = SessionStarterService()
        terminal = TerminalSessionManager()
        personaService = PersonaService(
            paths: paths,
            seedDirectory: LumiServicesResources.defaultPersonasDirectory,
            terminal: terminal,
            config: config
        )
        actionService = ActionService(
            paths: paths,
            seedDirectory: LumiServicesResources.defaultActionsDirectory,
            terminal: terminal,
            config: config
        )
        toasts = ToastStore()
        terminals = TerminalListStore(service: terminal, toasts: toasts)
        promptQueue = PromptQueueStore(service: terminal)
        sessionSchedule = SessionScheduleStore(starter: sessionStarter)
        repoStore = RepoStore(service: repoService)
        gitStore = GitStore(git: gitService, toasts: toasts)
        fileViewer = FileViewerStore(git: gitService, toasts: toasts)
        personasStore = PersonasStore(service: personaService, toasts: toasts)
        actionsStore = ActionsStore(service: actionService, toasts: toasts)
        settings = SettingsStore(config: config, toasts: toasts)
        usageStore = UsageStore(service: usageService)
        usageAutoRefresh = UsageAutoRefreshStore(usage: usageStore, activity: activityMonitor)
        remoteDashboardServer = RemoteDashboardServer(
            provider: TerminalServiceRemoteAdapter(service: terminal)
        )
        remoteDashboard = RemoteDashboardStore(server: remoteDashboardServer, toasts: toasts)
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

        // Seed asimetrisi (design/00 §3): persona ezilir, action modified_at'liyse korunur
        await personaService.seedDefaults()
        await actionService.seedDefaults()

        let appConfig = await config.config()
        terminal.setMaxTerminals(appConfig.maxTerminals)
        terminal.font = LumiFonts.mono(
            family: appConfig.terminalFontFamily,
            size: CGFloat(appConfig.terminalFontSize)
        )
        terminal.fontSmoothing = appConfig.terminalFontSmoothing
        terminal.theme = TerminalTheme.preset(id: appConfig.terminalTheme)
        terminal.cursorStyle = TerminalCursorStyleMapper.swiftTermStyle(
            shape: TerminalCursorShape.parse(appConfig.terminalCursorStyle),
            blink: appConfig.terminalCursorBlink
        )
        notifications.updateSettings(appConfig.notifications)
        sessionSchedule.update(appConfig.sessionTrigger)
        usageAutoRefresh.update(appConfig.usageAutoRefresh)
        repoStore.additionalPaths = appConfig.additionalPaths
        await repoService.setRoots(
            projectsRoot: appConfig.projectsRoot,
            additionalPaths: appConfig.additionalPaths
        )

        terminals.start()
        promptQueue.start()
        repoStore.start()
        personasStore.start()
        actionsStore.start()
        settings.start()
        await repoStore.reload()
        await workspace.load(repos: repoStore.repos)

        // First-run → onboarding sihirbazı (spec/13 §1.2, spec/22)
        workspace.isOnboardingActive = await config.isFirstRun()
        await notifications.requestPermissionIfNeeded()

        // Font ailesi + boyut tek NSFont'a birlikte çözülür; ikisinden hangisi
        // değişirse değişsin taze config'den fontu yeniden kurar.
        let rebuildFont: @MainActor () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let cfg = await self.config.config()
                self.terminal.font = LumiFonts.mono(
                    family: cfg.terminalFontFamily,
                    size: CGFloat(cfg.terminalFontSize)
                )
            }
        }
        configCoordinator.onTerminalFontSizeChanged = { _ in rebuildFont() }
        configCoordinator.onTerminalFontFamilyChanged = { rebuildFont() }
        configCoordinator.onTerminalFontSmoothingChanged = { [weak self] enabled in
            self?.terminal.fontSmoothing = enabled
        }
        configCoordinator.onTerminalThemeChanged = { [weak self] id in
            self?.terminal.theme = TerminalTheme.preset(id: id)
        }
        configCoordinator.onTerminalCursorChanged = { [weak self] shape, blink in
            self?.terminal.cursorStyle = TerminalCursorStyleMapper.swiftTermStyle(
                shape: shape, blink: blink
            )
        }
        configCoordinator.onSessionTriggerChanged = { [weak self] trigger in
            self?.sessionSchedule.update(trigger)
        }
        configCoordinator.onUsageAutoRefreshChanged = { [weak self] settings in
            self?.usageAutoRefresh.update(settings)
        }
        configCoordinator.start()
        startBridges()

        // Kullanım göstergesi ilk yükleme — arka planda, bootstrap'i bloklamaz
        // (auto-refresh YOK; sonrası manuel, design/05 + kullanıcı kararı).
        bridgeTasks.append(Task { @MainActor [weak self] in
            await self?.usageStore.loadInitialIfNeeded()
        })

        terminal.onTerminalViewFocused = { [weak self] id in
            self?.terminals.focus(id)
        }

        // Aktif repo değişimi: tek repo izlenir (spec/12 §12) + git/tree yüklenir
        workspace.onActiveRepoChanged = { [weak self] previous, current in
            guard let self else { return }
            Task { @MainActor in
                if let previous, previous != current {
                    await self.repoService.unwatchFileTree(repoPath: previous)
                }
                // Persona/action project scope'u aktif tab'ı izler
                await self.personasStore.setProject(current)
                await self.actionsStore.setProject(current)
                guard let current else { return }
                await self.repoService.watchFileTree(repoPath: current)
                await self.repoStore.loadFileTree(current)
                await self.gitStore.loadAll(current)
            }
        }
        // Bootstrap'te aktif tab varsa ilk yükleme (load() callback'ten önce kuruldu)
        if let active = workspace.activeTab {
            workspace.onActiveRepoChanged?(nil, active)
        }
    }

    private func startBridges() {
        // fileTreeChanged → file tree tazeleme + git panelleri canlılığı (spec/12 §12)
        let repoEventBridge = Task { @MainActor [weak self] in
            guard let service = self?.repoService else { return }
            let stream = await service.events()
            for await event in stream {
                guard let self else { return }
                if case .fileTreeChanged(let repoPath) = event {
                    await self.repoStore.loadFileTree(repoPath)
                    if self.workspace.activeTab == repoPath {
                        await self.gitStore.refresh(repoPath)
                    }
                }
            }
        }
        bridgeTasks.append(repoEventBridge)

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
                case .spawned, .titleChanged, .awaitingDecisionChanged, .bell:
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
        sessionSchedule.stop()
        usageAutoRefresh.stop()
        // Sunucu terminal aboneliği tutar — killAll'dan ÖNCE düşürülür
        await remoteDashboard.shutdown()
        terminal.killAll()
        await config.flushPendingWrites()
        // Temp system-prompt dosyaları (Electron will-quit paritesi + karar 11)
        try? FileManager.default.removeItem(at: paths.tempDir)
    }
}
