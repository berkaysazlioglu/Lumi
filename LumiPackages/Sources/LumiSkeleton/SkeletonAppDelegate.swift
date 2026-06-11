import AppKit
import LumiState
import LumiTerminal
import LumiUI
import SwiftUI

/// Faz 3 walking skeleton kabuğu: AppContainer composition root'u kullanır.
/// Bounds persistence, quit onayı, focus mode Faz 6'da — design/00 §2-3.
@MainActor
final class SkeletonAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let container = AppContainer()
    private var harness: P1Harness?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SkeletonMainMenu.install(actions: SkeletonMainMenu.Actions(
            target: self,
            newTerminal: #selector(newTerminal(_:)),
            closeTerminal: #selector(closeActiveTerminal(_:)),
            openRepoSelector: #selector(openRepoSelector(_:)),
            focusNext: #selector(focusNextTerminal(_:)),
            focusPrevious: #selector(focusPreviousTerminal(_:)),
            focusIndex: #selector(focusTerminalAtIndex(_:)),
            toggleLeftSidebar: #selector(toggleLeftSidebar(_:)),
            toggleRightSidebar: #selector(toggleRightSidebar(_:))
        ))

        Task { @MainActor in
            await container.start()
            buildWindow()

            if CommandLine.arguments.contains("--p1") {
                let repoPath = await container.defaultRepoPath()
                let harness = P1Harness(manager: container.terminal, store: container.terminals)
                harness.run(repoPath: repoPath)
                self.harness = harness
            }
        }
    }

    private func buildWindow() {
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
        window.center()

        let root = RootView(
            workspace: container.workspace,
            repoStore: container.repoStore,
            terminals: container.terminals,
            gitStore: container.gitStore,
            fileViewer: container.fileViewer,
            personasStore: container.personasStore,
            actionsStore: container.actionsStore,
            toasts: container.toasts,
            viewProvider: container.terminal.viewRegistry,
            highlighter: HighlightrEngine(),
            fileActions: RootView.FileActions(
                reveal: { [container] repoPath, relativePath in
                    container.system.revealInFinder(path: repoPath + "/" + relativePath)
                },
                trash: { [container] repoPath, relativePath in
                    Task { @MainActor in
                        await container.toasts.reporting {
                            try await container.system.trash(path: repoPath + "/" + relativePath)
                        }
                        await container.repoStore.loadFileTree(repoPath)
                    }
                }
            )
        )
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        observeWindowFocus(window)
    }

    /// Pencere odağı status makinelerine VE bildirim focus-guard'ına aynı
    /// semantikle akmalı (spec/00 §5, spec/10 §12, spec/13 §4).
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

    // MARK: - Menü aksiyonları (MenuActionDispatcher'ın Faz-3 hali)

    @objc private func newTerminal(_ sender: Any?) {
        guard let active = container.workspace.activeTab else { return }
        container.terminals.spawn(in: active)
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Faz 3: onay diyaloğu yok (Faz 6'da .terminateLater onay akışı);
        // PTY temizliği + bekleyen config yazımları garanti edilir
        Task { @MainActor in
            await container.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
