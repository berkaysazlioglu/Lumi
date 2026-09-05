import AppKit
import LumiKit
import LumiState
import LumiUI

/// AppKit kabuğu (design/03 §1-2). Refactor 3.6 sonrası yalnız **launch +
/// quit** akışı: pencere `MainWindowController`'da, kök view `RootViewFactory`'de,
/// menü aksiyonları `AppMenuCommands` + `MenuActionDispatcher`'da, bildirim
/// abonelikleri `AppLifecycleBridges`'te, servis/store grafiği
/// `AppComposition`'da.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pathsMode: LumiPaths.Mode
    private var composition: AppComposition!
    private var windowController: MainWindowController!
    private let dispatcher = MenuActionDispatcher()
    private let bridges = AppLifecycleBridges()
    private var harness: P1Harness?
    private var isShutdownComplete = false

    init(pathsMode: LumiPaths.Mode) {
        self.pathsMode = pathsMode
        super.init()
    }

    private var shared: SharedStores { composition.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LumiFonts.registerBundledFonts()
        installDockIcon()

        // Bundle'lıyken gerçek OS bildirimleri; swift run'da log presenter
        let unPresenter = UNNotificationPresenter.isAvailable ? UNNotificationPresenter() : nil
        let presenter: any NotificationPresenting = unPresenter ?? LogNotificationPresenter()
        composition = AppComposition.live(mode: pathsMode, notificationPresenter: presenter)
        windowController = MainWindowController(config: composition.registry.config)
        unPresenter?.onClick = { [weak self] terminalID in
            self?.shared.terminals.restoreAndFocus(terminalID)
            self?.windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        AppMenuCommands.register(in: dispatcher, shared: shared) { [weak self] in
            self?.openSettings()
        }
        MainMenuBuilder.install(dispatcher: dispatcher)

        Task { @MainActor in
            await composition.container.start()
            await buildWindow()
            runP1HarnessIfRequested()
        }
    }

    private func openSettings() {
        Task { @MainActor in
            await shared.settings.refresh() // her açılışta taze
            shared.dialogs.isSettingsOpen = true
        }
    }

    // MARK: - Pencere + köprüler

    private func buildWindow() async {
        let uiState = await composition.registry.config.uiState()
        windowController.onWindowShouldClose = { [weak self] in
            guard let self, !isShutdownComplete else { return true }
            // Çarpı (X) Cmd+Q ile aynı quit-onay akışına yönlendirilir.
            NSApp.terminate(nil)
            return false
        }
        windowController.onFullScreenTransition = { [weak self] in
            self?.refreshTerminalsAfterTransition()
        }

        let content = RootViewFactory(composition: composition).makeContentView()
        let window = windowController.install(contentView: content, uiState: uiState)

        bridges.observeWindowFocus(window) { [weak self] focused in
            self?.composition.registry.terminal.setWindowFocused(focused)
            self?.composition.registry.notifications.setWindowFocused(focused)
        }
        bridges.observeWake { [weak self] in
            self?.refreshAfterWake()
        }
        // Focus mode → traffic light senkronu (design/03 §2)
        shared.layout.onFocusModeChanged = { [weak self] active in
            self?.windowController.setTrafficLightsHidden(active)
        }
    }

    /// Fullscreen giriş/çıkışı terminal NSView'larını bayat/boş bırakabilir
    /// (AppKit içerik view'ını space-window'a taşır). Layout bir tur sonra
    /// oturduğundan hem hemen hem de sonraki runloop'ta onarılır.
    private func refreshTerminalsAfterTransition() {
        composition.registry.viewProvider.refreshAttachedViews()
        DispatchQueue.main.async { [weak self] in
            self?.composition.registry.viewProvider.refreshAttachedViews()
        }
    }

    private func refreshAfterWake() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await composition.repo.repoStore.reload()
            if let active = shared.navigation.activeRepoPath {
                await composition.repo.repoStore.loadFileTree(active)
                await composition.repo.gitStore.refresh(active)
            }
        }
    }

    /// P1 prototipi (design/04) — yalnız `--p1`.
    private func runP1HarnessIfRequested() {
        guard CommandLine.arguments.contains("--p1") else { return }
        Task { @MainActor in
            let repoPath = await composition.container.defaultRepoPath()
            let harness = composition.registry.makeP1Harness(store: shared.terminals)
            harness.run(repoPath: repoPath)
            self.harness = harness
        }
    }

    /// Dock ikonu: bundle'lıyken Info.plist'teki .icns geçerlidir; `swift run`
    /// (bundle'sız dev akışı) için ikon resource'tan runtime'da atanır.
    private func installDockIcon() {
        guard let url = Bundle.module.url(forResource: "icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            fputs("[lumi] dock ikonu yüklenemedi (resource eksik)\n", stderr)
            return
        }
        NSApp.applicationIconImage = image
    }

    // MARK: - Quit akışı (Cmd+Q, Dock, logout ve çarpı — HER yol onaydan geçer)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isShutdownComplete {
            return .terminateNow
        }
        let liveCount = shared.terminals.totalCount
        if liveCount == 0 {
            Task { @MainActor in await self.shutdownAndReply() }
            return .terminateLater
        }
        shared.dialogs.onQuitResolved = { [weak self] shouldQuit in
            if shouldQuit {
                Task { @MainActor in await self?.shutdownAndReply() }
            } else {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        shared.dialogs.presentQuitDialog(terminalCount: liveCount)
        return .terminateLater
    }

    private func shutdownAndReply() async {
        windowController.stop()
        bridges.stop()
        await composition.container.shutdown()
        isShutdownComplete = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
