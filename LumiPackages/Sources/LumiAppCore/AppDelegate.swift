import AppKit
import LumiKit
import LumiState
import LumiUI
import os

/// AppKit kabuğu (design/03 §1-2). Refactor 3.6 sonrası yalnız **launch +
/// quit** akışı: pencere `MainWindowController`'da, kök view `RootViewFactory`'de,
/// menü aksiyonları `AppMenuCommands` + `MenuActionDispatcher`'da, bildirim
/// abonelikleri `AppLifecycleBridges`'te, servis/store grafiği
/// `AppComposition`'da.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Teşhis izi (karar 83): quit akışı ve bildirim tıklaması.
    private static let logger = LumiLog.logger("lifecycle")
    private let pathsMode: LumiPaths.Mode
    private var composition: AppComposition!
    private var windowController: MainWindowController!
    private let dispatcher = MenuActionDispatcher()
    private let bridges = AppLifecycleBridges()
    private var harness: P1Harness?
    private var isShutdownComplete = false
    /// Menüde KURULU olan indeksli kısayol düzeni (karar 62). Config yan
    /// etkisi bununla karşılaştırılır — menü yalnız düzen değişince kurulur.
    private var installedShortcutStyle = IndexShortcutStyle.default
    private var shortcutStyleObserver: ConfigChangeBridge?

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
        // Teşhis günlüğünü etkinleştir (GUI app'te stderr kaybolur): ~/.lumi/logs/mac.log.
        // rlog çağrıları (remote bağlantı/komut/chat) buraya düşer.
        DiagLog.shared.configure(
            directory: composition.registry.paths.configDir.appendingPathComponent("logs"),
            filename: "mac.log")
        windowController = MainWindowController(config: composition.registry.config)
        unPresenter?.onClick = { [weak self] terminalID in
            Self.logger.log("notification clicked \(LumiLog.short(terminalID), privacy: .public)")
            self?.shared.terminals.restoreAndFocus(terminalID)
            self?.windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        AppMenuCommands.register(
            in: dispatcher,
            shared: shared,
            openSettings: { [weak self] in self?.openSettings(tab: .general) },
            openAbout: { [weak self] in self?.openSettings(tab: .about) },
            closeActiveProject: { [weak self] in
                self?.composition.shell.context.requestCloseActiveProject()
            }
        )
        // Config henüz diskten okunmadığı için menü varsayılan düzende kurulur;
        // gerçek düzen bootstrap'ten sonra uygulanır (karar 62).
        MainMenuBuilder.install(dispatcher: dispatcher, style: installedShortcutStyle)
        observeShortcutStyle()

        Task { @MainActor in
            await composition.container.start()
            applyShortcutStyle(shared.settings.current.indexShortcutStyle)
            await buildWindow()
            runP1HarnessIfRequested()
        }
    }

    // MARK: - İndeksli kısayol düzeni (karar 62)

    /// Ayar değişince menü yeniden kurulur: `NSMenuItem` kısayolları ancak
    /// yeni item'larla değişir, tablo da aynı düzenden türer.
    private func observeShortcutStyle() {
        let observer = ConfigChangeBridge { [weak self] old, new in
            guard old.indexShortcutStyle != new.indexShortcutStyle else { return }
            self?.applyShortcutStyle(new.indexShortcutStyle)
        }
        shortcutStyleObserver = observer
        composition.container.registerConfigObserver(observer)
    }

    private func applyShortcutStyle(_ style: IndexShortcutStyle) {
        guard installedShortcutStyle != style else { return }
        installedShortcutStyle = style
        MainMenuBuilder.install(dispatcher: dispatcher, style: style)
    }

    /// Karar 102: `Settings…` her zaman General'de, `About Lumi` About'ta açar.
    private func openSettings(tab: SettingsTab) {
        Task { @MainActor in
            await shared.settings.refresh() // her açılışta taze
            shared.dialogs.openSettings(tab: tab.rawValue)
        }
    }

    // MARK: - Pencere + köprüler

    private func buildWindow() async {
        let uiState = await composition.registry.config.uiState()
        windowController.onWindowShouldClose = { [weak self] in
            guard let self, !isShutdownComplete else { return true }
            Self.logger.log("window close requested → terminate")
            // Çarpı (X) Cmd+Q ile aynı quit-onay akışına yönlendirilir.
            NSApp.terminate(nil)
            return false
        }
        windowController.onFullScreenTransition = { [weak self] in
            self?.refreshTerminalsAfterTransition()
        }

        let content = RootViewFactory(composition: composition).makeContentView()
        let window = windowController.install(contentView: content, uiState: uiState)
        Self.logger.log("window installed")

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
        // Karar 61: ölçek → token çarpanı + arayüzün yeniden kurulması.
        // Store `Theme`'i ve AppKit'i tanımaz; köprü burada.
        shared.layout.onUIScaleChanged = { [weak self] scale in
            self?.applyUIScale(scale)
        }
        // Karar 63: yazı tipi → Theme token'ı + arayüzün yeniden kurulması.
        shared.layout.onUIFontFamilyChanged = { [weak self] family in
            self?.applyUIFontFamily(family)
        }
        applyUIScale(shared.layout.uiScale)
        applyUIFontFamily(shared.layout.uiFontFamily)
    }

    /// Ölçek değişiminin ÜÇ ayağı (karar 61):
    /// 1. `Theme.uiScale` — punto/boşluk token'larının çarpanı.
    /// 2. İçerik view'ının yeniden kurulması — SwiftUI static token okumalarını
    ///    izlemediği için mevcut ağaç eski ölçekte donar; `NSHostingView`
    ///    baştan kurulunca tüm body'ler yeni token'larla çalışır. Terminal
    ///    NSView'ları `TerminalViewRegistry`'de retain edildiğinden PTY kopmaz,
    ///    yalnız reparent olurlar.
    /// 3. Terminal fontu — SwiftTerm SwiftUI token'larını kullanmaz, ölçek
    ///    kullanıcının font boyutu ayarıyla ÇARPILARAK ayrıca uygulanır.
    ///
    /// `Theme.devicePixel` de burada tazelenir: token'lar cihaz pikseline
    /// yuvarlandığı için ızgaranın yürürlükteki ekranın backingScaleFactor'ünü
    /// yansıtması gerekir. Erken çıkış kontrolü ızgarayı DA gözetir, yoksa
    /// açılışta ölçek zaten 1'ken ilk okuma hiç uygulanmazdı.
    private func applyUIScale(_ scale: CGFloat) {
        let pixel = Self.devicePixelSize(for: windowController.window)
        let gridChanged = Theme.devicePixel != pixel
        Theme.devicePixel = pixel
        guard Theme.uiScale != scale || gridChanged else { return }
        Theme.uiScale = scale
        applyTerminalFont()
        rebuildContentView()
    }

    /// Pencerenin (yoksa ana ekranın) bir cihaz pikselinin punto karşılığı.
    /// Ekran okunamazsa Retina varsayılır — 1x tahmin etmek her token'ı bir
    /// kademe kaba bir ızgaraya oturtur ve arayüzü gereksiz yere bozardı.
    private static func devicePixelSize(for window: NSWindow?) -> CGFloat {
        let factor = window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        return factor > 0 ? 1 / factor : 0.5
    }

    /// Karar 63: yazı tipi değişimi ölçeğin ikinci ayağını paylaşır (içerik
    /// view'ının yeniden kurulması). Terminal fontu ETKİLENMEZ — o ayrı bir
    /// ayardır ve zaten JetBrains Mono'yu varsayılan alır.
    private func applyUIFontFamily(_ family: UIFontFamily) {
        guard Theme.uiFontFamily != family else { return }
        Theme.uiFontFamily = family
        rebuildContentView()
    }

    /// SwiftUI static token okumalarını izlemediği için mevcut ağaç eski
    /// değerlerde donar; `NSHostingView` baştan kurulunca tüm body'ler yeni
    /// token'larla çalışır. Terminal NSView'ları `TerminalViewRegistry`'de
    /// retain edildiğinden PTY kopmaz, yalnız reparent olurlar.
    private func rebuildContentView() {
        let content = RootViewFactory(composition: composition).makeContentView()
        windowController.replaceContentView(content)
        // Reparent sonrası canlı terminal view'ları yeni host'lara oturur.
        composition.registry.viewProvider.refreshAttachedViews()
    }

    private func applyTerminalFont() {
        let config = shared.settings.current
        composition.registry.terminal.applyFont(LumiFonts.mono(
            family: config.terminalFontFamily,
            size: Theme.scaledFontSize(CGFloat(config.terminalFontSize))
        ))
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
        let liveCount = shared.terminals.totalCount
        Self.logger.log("applicationShouldTerminate live=\(liveCount) shutdownComplete=\(self.isShutdownComplete)")
        if isShutdownComplete {
            return .terminateNow
        }
        if liveCount == 0 {
            Task { @MainActor in await self.shutdownAndReply() }
            return .terminateLater
        }
        shared.dialogs.onQuitResolved = { [weak self] shouldQuit in
            Self.logger.log("quit dialog resolved: \(shouldQuit)")
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
        Self.logger.log("shutdownAndReply begin")
        windowController.stop()
        bridges.stop()
        await composition.container.shutdown()
        isShutdownComplete = true
        Self.logger.log("shutdownAndReply: replying terminate")
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.logger.log("applicationWillTerminate")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
