import AppKit
import LumiKit
import LumiState
import LumiTerminal
import LumiUI
import SwiftUI

/// AppKit kabuğu (design/03 §1-2): pencere/bounds persistence, quit-onay
/// akışı (.terminateLater — Cmd+Q dahil HER yol), menü (kısayolların tek
/// kaynağı), sleep/wake, focus-mode traffic-light senkronu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let boundsPersistDebounce: TimeInterval = 0.5

    private var window: NSWindow?
    private var container: AppContainer!
    private var harness: P1Harness?
    private var pendingBoundsPersist: DispatchWorkItem?
    private var isRestoringWindow = true
    private var isShutdownComplete = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LumiFonts.registerBundledFonts()
        installDockIcon()

        // Bundle'lıyken gerçek OS bildirimleri; swift run'da log presenter
        let unPresenter = UNNotificationPresenter.isAvailable ? UNNotificationPresenter() : nil
        let presenter: any NotificationPresenting = unPresenter ?? LogNotificationPresenter()
        container = AppContainer(notificationPresenter: presenter)
        unPresenter?.onClick = { [weak self] terminalID in
            self?.container.terminals.restoreAndFocus(terminalID)
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        installMenu()

        Task { @MainActor in
            await container.start()
            await buildWindow()
            wireFocusMode()
            observeWake()

            if CommandLine.arguments.contains("--p1") {
                let repoPath = await container.defaultRepoPath()
                let harness = P1Harness(manager: container.terminal, store: container.terminals)
                harness.run(repoPath: repoPath)
                self.harness = harness
            }
        }
    }

    private func installMenu() {
        MainMenuBuilder.install(actions: MainMenuBuilder.Actions(
            target: self,
            newTerminal: #selector(newTerminal(_:)),
            closeTerminal: #selector(closeActiveTerminal(_:)),
            openRepoSelector: #selector(openRepoSelector(_:)),
            focusNext: #selector(focusNextTerminal(_:)),
            focusPrevious: #selector(focusPreviousTerminal(_:)),
            focusIndex: #selector(focusTerminalAtIndex(_:)),
            toggleLeftSidebar: #selector(toggleLeftSidebar(_:)),
            toggleRightSidebar: #selector(toggleRightSidebar(_:)),
            openSettings: #selector(openSettings(_:)),
            toggleFocusMode: #selector(toggleFocusMode(_:))
        ))
    }

    // MARK: - Pencere (spec/30: bounds ui-state.json'da, frameAutosave YOK — karar 9)

    private func buildWindow() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 1000, height: 600)
        window.backgroundColor = NSColor(srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x12 / 255, alpha: 1)

        let uiState = await container.config.uiState()
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let saved = uiState.windowBounds,
           let valid = WindowBoundsValidator.validated(saved, screens: screens) {
            window.setFrame(
                NSRect(x: valid.x, y: valid.y, width: valid.width, height: valid.height),
                display: false
            )
        } else {
            window.center()
        }

        let root = RootView(
            workspace: container.workspace,
            repoStore: container.repoStore,
            terminals: container.terminals,
            gitStore: container.gitStore,
            fileViewer: container.fileViewer,
            personasStore: container.personasStore,
            actionsStore: container.actionsStore,
            settings: container.settings,
            toasts: container.toasts,
            viewProvider: container.terminal.viewRegistry,
            highlighter: HighlightrEngine(),
            fileActions: makeFileActions(),
            shellActions: makeShellActions()
        )
        window.contentView = NSHostingView(rootView: root)

        // Maximize flag'i show'dan ÖNCE uygulanır (flash önleme — spec/30)
        if uiState.windowMaximized == true, !window.isZoomed {
            window.zoom(nil)
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window

        observeWindowFocus(window)
        observeWindowBounds(window)
        isRestoringWindow = false
    }

    private func makeFileActions() -> RootView.FileActions {
        RootView.FileActions(
            reveal: { [container] repoPath, relativePath in
                container?.system.revealInFinder(path: repoPath + "/" + relativePath)
            },
            trash: { [container] repoPath, relativePath in
                guard let container else { return }
                Task { @MainActor in
                    await container.toasts.reporting {
                        try await container.system.trash(path: repoPath + "/" + relativePath)
                    }
                    await container.repoStore.loadFileTree(repoPath)
                }
            }
        )
    }

    private func makeShellActions() -> RootView.ShellActions {
        RootView.ShellActions(
            chooseFolder: { [container] in
                await container?.system.chooseFolder()
            },
            runChecks: { [container] in
                guard let container else { return [] }
                let provider = await container.config.config().aiProvider
                return await container.system.runChecks(selectedProvider: provider)
            },
            fixCheck: { [container] checkID in
                guard let container else { return }
                let url: URL?
                switch checkID {
                case "claude-cli":
                    url = URL(string: "https://code.claude.com/docs/en/setup")
                case "codex-cli":
                    url = URL(string: "https://github.com/openai/codex")
                default:
                    url = nil
                }
                if let url {
                    container.toasts.reporting {
                        try container.system.openExternal(url)
                    }
                }
            }
        )
    }

    // MARK: - Bounds persistence (500ms debounce; zoom'dayken bounds yazılmaz)

    private func observeWindowBounds(_ window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleBoundsPersist()
                }
            }
        }
    }

    private func scheduleBoundsPersist() {
        guard !isRestoringWindow, let window else { return }
        pendingBoundsPersist?.cancel()
        let isZoomed = window.isZoomed
        let frame = window.frame
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.container.config.updateUIState { state in
                    state.windowMaximized = isZoomed
                    if !isZoomed {
                        state.windowBounds = WindowBounds(
                            x: frame.origin.x,
                            y: frame.origin.y,
                            width: frame.width,
                            height: frame.height
                        )
                    }
                }
            }
        }
        pendingBoundsPersist = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.boundsPersistDebounce, execute: work
        )
    }

    // MARK: - Odak ve uyanma köprüleri

    private func observeWindowFocus(_ window: NSWindow) {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.container.terminal.setWindowFocused(true)
                self?.container.notifications.setWindowFocused(true)
            }
        }
        center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.container.terminal.setWindowFocused(false)
                self?.container.notifications.setWindowFocused(false)
            }
        }
    }

    /// Uyanmada watcher'lar kaçırmış olabilir → repo listesi + aktif repo verileri
    /// tazelenir (spec/00 §5; terminal state'i tek process'te zaten kopmaz).
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let container = self?.container else { return }
                Task { @MainActor in
                    await container.repoStore.reload()
                    if let active = container.workspace.activeTab {
                        await container.repoStore.loadFileTree(active)
                        await container.gitStore.refresh(active)
                    }
                }
            }
        }
    }

    // MARK: - Focus mode → traffic light senkronu (design/03 §2)

    private func wireFocusMode() {
        container.workspace.onFocusModeChanged = { [weak self] active in
            self?.setTrafficLightsHidden(active)
        }
    }

    private func setTrafficLightsHidden(_ hidden: Bool) {
        guard let window else { return }
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = hidden
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

    // MARK: - Menü aksiyonları

    @objc private func newTerminal(_ sender: Any?) {
        guard let active = container.workspace.activeTab else { return }
        // Spec/20 §6 paritesi: provider terminali = shell + launch komutu
        container.terminals.spawn(
            in: active,
            command: container.settings.current.aiProvider.launchCommand
        )
    }

    @objc private func closeActiveTerminal(_ sender: Any?) {
        guard let activeID = container.terminals.activeTerminalID else { return }
        container.terminals.close(activeID)
    }

    @objc private func openRepoSelector(_ sender: Any?) {
        container.workspace.isRepoSelectorOpen = true
    }

    @objc private func focusNextTerminal(_ sender: Any?) {
        guard let active = container.workspace.activeTab else { return }
        container.terminals.focusNext(in: active)
    }

    @objc private func focusPreviousTerminal(_ sender: Any?) {
        guard let active = container.workspace.activeTab else { return }
        container.terminals.focusPrevious(in: active)
    }

    @objc private func focusTerminalAtIndex(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let active = container.workspace.activeTab else { return }
        container.terminals.focusIndex(item.tag - 1, in: active)
    }

    @objc private func toggleLeftSidebar(_ sender: Any?) {
        container.workspace.toggleLeftSidebar()
    }

    @objc private func toggleRightSidebar(_ sender: Any?) {
        container.workspace.toggleRightSidebar()
    }

    @objc private func openSettings(_ sender: Any?) {
        Task { @MainActor in
            await container.settings.refresh() // her açılışta taze (spec/22)
            container.workspace.isSettingsOpen = true
        }
    }

    @objc private func toggleFocusMode(_ sender: Any?) {
        container.workspace.toggleFocusMode()
    }

    // MARK: - Quit akışı (spec/30: Cmd+Q dahil HER yol onaydan geçer)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isShutdownComplete {
            return .terminateNow
        }
        let liveCount = container.terminals.totalCount
        if liveCount == 0 {
            Task { @MainActor in
                await self.shutdownAndReply()
            }
            return .terminateLater
        }
        container.workspace.onQuitResolved = { [weak self] shouldQuit in
            if shouldQuit {
                Task { @MainActor in
                    await self?.shutdownAndReply()
                }
            } else {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        container.workspace.presentQuitDialog(terminalCount: liveCount)
        return .terminateLater
    }

    private func shutdownAndReply() async {
        await container.shutdown()
        isShutdownComplete = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
