import AppKit
import LumiKit

/// Canlı terminal NSView'larının sahibi (design/03 §3 — yük taşıyan desen).
///
/// View'lar PTY ömrü boyunca burada retain edilir; SwiftUI yalnız attach/detach
/// eder. Re-render hiçbir koşulda terminal state'ini yok edemez. Detach edilen
/// oturumda gizli-terminal politikası devreye girer (coalescing genişler, çizim durur).
@MainActor
public final class TerminalViewRegistry: TerminalViewProviding {
    private struct Entry {
        let view: NSView
        let onVisibilityChange: (Bool) -> Void
    }

    private var entries: [TerminalID: Entry] = [:]

    func register(view: NSView, for id: TerminalID, onVisibilityChange: @escaping (Bool) -> Void) {
        entries[id] = Entry(view: view, onVisibilityChange: onVisibilityChange)
        // Spawn anında henüz hiçbir container'a bağlı değil — gizli politikayla başlar
        onVisibilityChange(false)
    }

    func unregister(_ id: TerminalID) {
        entries[id]?.view.removeFromSuperview()
        entries.removeValue(forKey: id)
    }

    /// Click-to-focus için ters arama: first responder olan view → terminal id.
    func terminalID(for view: NSView) -> TerminalID? {
        entries.first { $0.value.view === view }?.key
    }

    public func attachView(for id: TerminalID, into container: NSView) {
        guard let entry = entries[id] else { return }
        if entry.view.superview === container {
            entry.view.frame = container.bounds
            return
        }
        entry.view.removeFromSuperview()
        entry.view.frame = container.bounds
        entry.view.autoresizingMask = [.width, .height]
        container.addSubview(entry.view)
        // "Görünür olunca fit" garantisi: frame ataması SwiftTerm'in cols/rows
        // hesabını tetikler; sizeChanged delegate'i resize'ı PTY'ye iletir (spec/20)
        entry.onVisibilityChange(true)
    }

    public func detachView(for id: TerminalID) {
        guard let entry = entries[id] else { return }
        entry.view.removeFromSuperview()
        entry.onVisibilityChange(false)
    }
}
