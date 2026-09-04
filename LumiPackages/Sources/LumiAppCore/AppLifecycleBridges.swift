import AppKit

/// Uygulama yaşam döngüsü bildirimlerinin köprüsü (refactor 3.6).
///
/// `AppDelegate` bunları eskiden token'sız kuruyordu — kaldırma yolu yoktu.
/// Token'lar burada saklanır; `stop()` (ve nesne yok olurken `deinit`) hepsini
/// bırakır.
@MainActor
final class AppLifecycleBridges {
    /// `deinit` MainActor'da koşmadığı için token'lar izolasyonsuz bir kutuda
    /// tutulur; `NotificationCenter.removeObserver` thread-safe'dir.
    private final class TokenBox: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(center: NotificationCenter, token: NSObjectProtocol)] = []

        func append(_ center: NotificationCenter, _ token: NSObjectProtocol) {
            lock.withLock { entries.append((center, token)) }
        }

        func drain() {
            let current = lock.withLock { () -> [(NotificationCenter, NSObjectProtocol)] in
                let copy = entries.map { ($0.center, $0.token) }
                entries.removeAll()
                return copy
            }
            for (center, token) in current {
                center.removeObserver(token)
            }
        }
    }

    private let tokens = TokenBox()

    init() {}

    /// Pencere odağı → terminal + bildirim servisleri (design/03 §2 focus köprüsü;
    /// bildirim semantiği buna bağlıdır).
    func observeWindowFocus(_ window: NSWindow, onChange: @escaping @MainActor (Bool) -> Void) {
        add(.default, NSWindow.didBecomeKeyNotification, object: window) { onChange(true) }
        add(.default, NSWindow.didResignKeyNotification, object: window) { onChange(false) }
    }

    /// Uyanmada watcher'lar kaçırmış olabilir → repo listesi + aktif repo
    /// verileri tazelenir (Electron paritesi; terminal state'i tek process'te
    /// zaten kopmaz).
    func observeWake(_ handler: @escaping @MainActor () -> Void) {
        add(
            NSWorkspace.shared.notificationCenter,
            NSWorkspace.didWakeNotification,
            object: nil,
            handler
        )
    }

    func stop() {
        tokens.drain()
    }

    deinit {
        tokens.drain()
    }

    private func add(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject?,
        _ handler: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        tokens.append(center, token)
    }
}
