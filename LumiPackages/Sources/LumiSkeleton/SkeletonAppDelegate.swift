import AppKit
import LumiState
import LumiTerminal
import LumiUI
import SwiftUI

/// Faz 2 walking skeleton kabuğu: AppContainer composition root'u kullanır.
/// Pencere davranışlarının tamamı (bounds persistence, quit onayı, tam menü)
/// Faz 3/6'da — design/00 §2-3.
@MainActor
final class SkeletonAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let container = AppContainer()
    private var harness: P1Harness?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SkeletonMainMenu.install(
            closeTerminalTarget: self,
            closeTerminalAction: #selector(closeActiveTerminal(_:))
        )

        Task { @MainActor in
            await container.start()
            let repoPath = await container.defaultRepoPath()
            buildWindow(repoPath: repoPath)

            if CommandLine.arguments.contains("--p1") {
                let harness = P1Harness(manager: container.terminal, store: container.terminals)
                harness.run(repoPath: repoPath)
                self.harness = harness
            }
        }
    }

    private func buildWindow(repoPath: String) {
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
            store: container.terminals,
            toasts: container.toasts,
            viewProvider: container.terminal.viewRegistry,
            repoPath: repoPath
        )
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        observeWindowFocus(window)
    }

    /// Pencere odağı status makinelerine AYNI semantikle akmalı — bildirim
    /// sistemi buna bağlı (spec/00 §5, spec/10 §12).
    private func observeWindowFocus(_ window: NSWindow) {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.container.terminal.setWindowFocused(true) }
        }
        center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.container.terminal.setWindowFocused(false) }
        }
    }

    @objc private func closeActiveTerminal(_ sender: Any?) {
        guard let activeID = container.terminals.activeTerminalID else { return }
        container.terminals.close(activeID)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Faz 2: onay diyaloğu yok (Faz 6'da .terminateLater akışı);
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
