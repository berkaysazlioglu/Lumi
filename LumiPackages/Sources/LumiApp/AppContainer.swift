import Foundation
import LumiKit
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
    let notifications: any NotificationServicing
    /// Sağlayıcı başına kullanım servisi (karar 32).
    let usageServices: [AgentProvider: any UsageServicing]
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
    let settings: SettingsStore
    let usageStores: [AgentProvider: UsageStore]
    let usageAutoRefresh: UsageAutoRefreshStore
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
        usageServices = [
            .claude: ClaudeUsageService(),
            .codex: CodexUsageService(),
        ]
        activityMonitor = SystemActivityMonitor()
        sessionStarter = SessionStarterService()
        terminal = TerminalSessionManager()
        toasts = ToastStore()
        terminals = TerminalListStore(service: terminal, toasts: toasts)
        promptQueue = PromptQueueStore(service: terminal)
        sessionSchedule = SessionScheduleStore(starter: sessionStarter)
        repoStore = RepoStore(service: repoService)
        gitStore = GitStore(git: gitService, toasts: toasts)
        fileViewer = FileViewerStore(git: gitService, toasts: toasts)
        settings = SettingsStore(config: config, toasts: toasts)
        let stores = usageServices.mapValues { UsageStore(service: $0) }
        usageStores = stores
        usageAutoRefresh = UsageAutoRefreshStore(
            stores: AgentProvider.allCases.compactMap { stores[$0] },
            activity: activityMonitor
        )
        workspace = WorkspaceStore(config: config, terminals: terminals)
        configCoordinator = ConfigSideEffectCoordinator(
            config: config,
            terminal: terminal,
            repo: repoService,
            repoStore: repoStore,
            notifications: notifications
        )
    }

    /// Sıra-bağımlı bootstrap (design/00 §3): dizinler →
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
        terminal.font = LumiFonts.mono(
            family: appConfig.terminalFontFamily,
            size: CGFloat(appConfig.terminalFontSize)
        )
        terminal.cursorStyle = TerminalCursorStyleMapper.swiftTermStyle(
            shape: TerminalCursorShape.parse(appConfig.terminalCursorStyle),
            blink: appConfig.terminalCursorBlink
        )
        notifications.updateSettings(appConfig.notifications)
        terminals.autoMinimizeOnSend = appConfig.autoMinimizeOnSend
        sessionSchedule.update(appConfig.sessionTrigger)
        usageAutoRefresh.update(appConfig.usageAutoRefresh)
        applyUsageIndicators(appConfig.usageIndicators)
        repoStore.additionalPaths = appConfig.additionalPaths
        await repoService.setRoots(
            projectsRoot: appConfig.projectsRoot,
            additionalPaths: appConfig.additionalPaths
        )

        terminals.start()
        promptQueue.start()
        repoStore.start()
        settings.start()
        await repoStore.reload()
        await workspace.load(repos: repoStore.repos)

        // First-run → onboarding sihirbazı
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
        configCoordinator.onTerminalCursorChanged = { [weak self] shape, blink in
            self?.terminal.cursorStyle = TerminalCursorStyleMapper.swiftTermStyle(
                shape: shape, blink: blink
            )
        }
        configCoordinator.onAutoMinimizeOnSendChanged = { [weak self] enabled in
            self?.terminals.autoMinimizeOnSend = enabled
        }
        configCoordinator.onSessionTriggerChanged = { [weak self] trigger in
            self?.sessionSchedule.update(trigger)
        }
        configCoordinator.onUsageAutoRefreshChanged = { [weak self] settings in
            self?.usageAutoRefresh.update(settings)
        }
        configCoordinator.onUsageIndicatorsChanged = { [weak self] indicators in
            guard let self else { return }
            self.applyUsageIndicators(indicators)
            // Yeni açılan sağlayıcı boş kalmasın: kapı açıldıktan sonra ilk yükleme.
            self.bridgeTasks.append(Task { @MainActor [weak self] in
                await self?.loadEnabledUsageIndicators()
            })
        }
        configCoordinator.start()
        startBridges()

        // Kullanım göstergeleri ilk yükleme — arka planda, bootstrap'i bloklamaz
        // (auto-refresh YOK; sonrası manuel, design/05 + kullanıcı kararı).
        bridgeTasks.append(Task { @MainActor [weak self] in
            await self?.loadEnabledUsageIndicators()
        })

        terminal.onTerminalViewFocused = { [weak self] id in
            self?.terminals.focus(id)
        }

        // Aktif repo değişimi: tek repo izlenir + git/tree yüklenir
        workspace.onActiveRepoChanged = { [weak self] previous, current in
            guard let self else { return }
            Task { @MainActor in
                if let previous, previous != current {
                    await self.repoService.unwatchFileTree(repoPath: previous)
                }
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

        await resumeClaudeSessions()
    }

    private func startBridges() {
        // fileTreeChanged → file tree tazeleme + git panelleri canlılığı
        // Coalescing (karar 28): tarama uçuştayken gelen event'ler tek bir
        // follow-up'a çöker; for-await döngüsü asla taramayı beklemez.
        let refreshCoalescer = KeyedRefreshCoalescer { [weak self] repoPath in
            guard let self else { return }
            await self.repoStore.loadFileTree(repoPath)
            if self.workspace.activeTab == repoPath {
                await self.gitStore.refresh(repoPath)
            }
        }
        let repoEventBridge = Task { @MainActor [weak self] in
            guard let service = self?.repoService else { return }
            let stream = await service.events()
            for await event in stream {
                guard self != nil else { return }
                if case .fileTreeChanged(let repoPath) = event {
                    refreshCoalescer.request(repoPath)
                }
            }
        }
        bridgeTasks.append(repoEventBridge)

        // Terminal status event'leri → NotificationService (onChange köprüsü)
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
                    // Minimize istisnası: bildirim tıklaması restore + focus
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

    // MARK: - Kullanım göstergeleri (karar 32)

    /// Config'teki açık/kapalı durumunu store'lara yansıtır. Kapı store'un
    /// içindedir: kapalı store hiçbir istek atmaz (manuel refresh dahil).
    private func applyUsageIndicators(_ indicators: UsageIndicators) {
        for (provider, store) in usageStores {
            store.setEnabled(indicators.isEnabled(provider))
        }
    }

    /// Açık göstergelerin ilk yüklemesi. Kapalı store'da `loadInitialIfNeeded`
    /// zaten no-op'tur; sıra `AgentProvider.allCases` ile deterministiktir.
    private func loadEnabledUsageIndicators() async {
        for provider in AgentProvider.allCases {
            await usageStores[provider]?.loadInitialIfNeeded()
        }
    }

    /// Karar 23: önceki graceful quit'te persist edilen claude oturumlarını
    /// açık tab'ı duran repo'larda `claude --resume <id> || claude` ile yeniden
    /// spawn eder. Kayıtlar TEK SEFERLİK tüketilir (önce boşaltılır — spawn
    /// başarısız olsa bile bayat liste sonraki açılışlara sarkmaz).
    private func resumeClaudeSessions() async {
        let entries = await config.uiState().resumeSessions
        guard !entries.isEmpty else { return }
        await config.updateUIState { $0.resumeSessions = [] }
        for entry in entries where workspace.openTabs.contains(entry.repoPath) {
            terminals.spawn(
                in: entry.repoPath,
                command: ClaudeSessionCommand.resumeCommand(sessionID: entry.sessionID)
            )
        }
    }

    func defaultRepoPath() async -> String {
        let appConfig = await config.config()
        return appConfig.projectsRoot.isEmpty ? NSHomeDirectory() : appConfig.projectsRoot
    }

    func shutdown() async {
        bridgeTasks.forEach { $0.cancel() }
        sessionSchedule.stop()
        usageAutoRefresh.stop()
        // Karar 23: killAll'dan ÖNCE canlı claude oturumları persist edilir —
        // bir sonraki açılış aynı chat'lerden devam eder. Graceful /exit gerekmez:
        // transcript kill sonrası da sağlamdır (ampirik doğrulama karar 23'te).
        let resumeSessions = terminal.terminals.compactMap { meta in
            meta.claudeSessionID.map {
                ResumeSession(repoPath: meta.repoPath, sessionID: $0)
            }
        }
        await config.updateUIState { $0.resumeSessions = resumeSessions }
        terminal.killAll()
        await config.flushPendingWrites()
        // Temp dizini (Electron will-quit paritesi + karar 11)
        try? FileManager.default.removeItem(at: paths.tempDir)
    }
}
