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
        /// Emülatör buffer'ından tam yeniden çizim (updateFullScreen) — SIGWINCH
        /// poke'u İÇERMEZ; frame-oturma yolunda PTY resize zinciri SIGWINCH'i
        /// zaten üretir, ek poke pencere resize'ında TUI'yi spam'lerdi.
        let onRedraw: () -> Void
    }

    private var entries: [TerminalID: Entry] = [:]

    func register(
        view: NSView,
        for id: TerminalID,
        onVisibilityChange: @escaping (Bool) -> Void,
        onRedraw: @escaping () -> Void = {}
    ) {
        entries[id] = Entry(view: view, onVisibilityChange: onVisibilityChange, onRedraw: onRedraw)
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
        let bounds = container.bounds
        if entry.view.superview === container {
            // Reassert yolu (host her layout'ta çağırır): frame GERÇEK boyuta
            // oturduğunda buffer'dan tam çizim istenir. Tab değişiminde host
            // yeniden yaratılır ve ilk attach 0×0 bounds'la gelir — o anda
            // yapılan repaint'in setNeedsDisplay'i no-op kalır; içerik ancak
            // burada, boyut oturunca görünür olur (boş kart bug'ının onarımı).
            if !bounds.isEmpty, !entry.view.frame.equalTo(bounds) {
                entry.view.frame = bounds
                entry.view.needsDisplay = true
                entry.onRedraw()
            }
            return
        }
        entry.view.removeFromSuperview()
        // 0×0 container'a (SwiftUI layout vermeden önceki makeNSView anı) frame
        // ATANMAZ: SwiftTerm'i sıfıra küçültmek emülatörü gereksiz resize eder ve
        // ardından gelen repaint'in setNeedsDisplay(bounds)'unu no-op yapardı.
        // Eski frame korunur; layout gelince yukarıdaki reassert dalı oturtur.
        if !bounds.isEmpty {
            entry.view.frame = bounds
        }
        entry.view.autoresizingMask = [.width, .height]
        container.addSubview(entry.view)
        // "Görünür olunca fit" garantisi: frame ataması SwiftTerm'in cols/rows
        // hesabını tetikler; sizeChanged delegate'i resize'ı PTY'ye iletir (spec/20).
        // Buffer'dan tam yeniden çizim: re-attach sonrası (grid round-trip) emülatör
        // içeriği zaten elde; görünmesi için tüm bounds dirty işaretlenir.
        entry.view.needsDisplay = true
        entry.onVisibilityChange(true)
    }

    /// Fullscreen geçişi / pencere-space değişimi sonrası onarım. AppKit, native
    /// fullscreen'e girip çıkarken içerik view'ını ayrı bir space-window'a taşır;
    /// dönüşte SwiftTerm otomatik repaint etmez ve attach/detach yarışında frame
    /// bayat (hatta sıfır) kalabilir → kart bozuk/boş görünür. Bağlı her view
    /// superview bounds'una yeniden hizalanır (delta varsa SwiftTerm sizeChanged →
    /// PTY resize zinciri kendiliğinden tetiklenir) ve redraw işaretlenir. Grid
    /// round-trip onarımının (attachView'daki needsDisplay) fullscreen analogudur.
    public func refreshAttachedViews() {
        for entry in entries.values {
            guard let superview = entry.view.superview, !superview.bounds.isEmpty else { continue }
            entry.view.frame = superview.bounds
            entry.view.needsDisplay = true
            // setHidden(false) + requestRepaint → SIGWINCH; needsDisplay tek başına
            // TUI'yi yeniden çizdirmediğinden (boş kart) repaint sinyali şart.
            entry.onVisibilityChange(true)
        }
    }

    public func detachView(for id: TerminalID, from container: NSView) {
        // Reparenting yarışı (grid↔maximize round-trip): SwiftUI, paylaşılan tek
        // NSView'ı yeni host'a taşırken eski host'u dismantle ediyor; sıralama
        // tersine dönerse ölmekte olan host canlı view'ı öksüz bırakıp kartı boş
        // (ve resize'a sağır) kalmaya itiyordu. Kaldırmayı bir sonraki runloop'a
        // ertele; o ana dek view başka bir container'a taşınmışsa (yeni host claim
        // etti ya da container kendini reassert etti) DOKUNMA — yalnız hâlâ bu
        // container'daysa gerçekten sök ve gizle.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let entry = self.entries[id] else { return }
                guard entry.view.superview === container else { return }
                entry.view.removeFromSuperview()
                entry.onVisibilityChange(false)
            }
        }
    }
}
