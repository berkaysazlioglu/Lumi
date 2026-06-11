import AppKit
import LumiState
import LumiTerminal
import LumiUI
import SwiftUI

/// Faz 1 walking skeleton kabuğu. Gerçek app target'ın (AppDelegate +
/// MainWindowController + AppContainer, design/00 §2-3) öncülüdür; pencere
/// davranışlarının tamamı (bounds persistence, quit onayı, menü) Faz 2+/6'da.
@MainActor
final class SkeletonAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let manager = TerminalSessionManager()
    private var store: TerminalListStore?
    private var harness: P1Harness?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = TerminalListStore(service: manager)
        store.start()
        self.store = store

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

        let repoPath = NSHomeDirectory()
        let root = RootView(store: store, viewProvider: manager.viewRegistry, repoPath: repoPath)
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        observeWindowFocus(window)

        if CommandLine.arguments.contains("--p1") {
            let harness = P1Harness(manager: manager, store: store)
            harness.run(repoPath: repoPath)
            self.harness = harness
        }
    }

    /// Pencere odağı status makinelerine AYNI semantikle akmalı — bildirim
    /// sistemi buna bağlı (spec/00 §5, spec/10 §12).
    private func observeWindowFocus(_ window: NSWindow) {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.manager.setWindowFocused(true) }
        }
        center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.manager.setWindowFocused(false) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Faz 1: onay diyaloğu yok (Faz 6'da .terminateLater akışı); PTY temizliği garanti
        manager.killAll()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
