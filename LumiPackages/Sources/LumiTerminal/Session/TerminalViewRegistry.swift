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
        /// Görünürlük geçişinin TEK kanalı (Faz 4.4/4B): yüzey durumu (coalescer
        /// aralığı + odak) VE buffer'dan tam yeniden çizim bu callback'ten akar.
        /// Ayrı bir `onRedraw` kancası vardı; her iki tetikleyicisinde
        /// (`attachView`, `refreshAttachedViews`) görünürlük sinyaliyle birlikte
        /// çağrıldığı için ikinci bir tam çizimden başka şey üretmiyordu.
        /// Yalnız GERÇEK attach olayında çağrılır — frame deltasına bağlanmaz
        /// (refactor 4.5): layout geçişi başına tam çizim, resize/animasyonda
        /// N terminal × frame maliyeti doğuruyordu.
        let onVisibilityChange: (Bool) -> Void
    }

    private var entries: [TerminalID: Entry] = [:]

    func register(
        view: NSView,
        for id: TerminalID,
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
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

    /// Hücre boyutu değişti (font) → host'tan yeni bir layout geçişi iste.
    /// Oturum superview'a dokunmaz (katman sınırı, Faz 4.1); yerleşim otoritesi
    /// host'tadır — burada yalnız "yeniden yerleş" sinyali verilir.
    func invalidateLayout(for id: TerminalID) {
        entries[id]?.view.superview?.needsLayout = true
    }

    /// Reparent + görünürlük sinyali. **Frame'e DOKUNMAZ** (refactor 4.5): yerleşim
    /// otoritesi tek yerdedir — `TerminalHostContainer.pinTerminalView` →
    /// `TerminalGridFit.fit`. Host her AppKit layout geçişinde kendini onarmak için
    /// bu metodu çağırır (reassert); zaten bağlıysa burada hiçbir iş yapılmaz, yoksa
    /// her frame'de görünürlük sinyali (→ tam çizim) tetiklenir ve resize/animasyon
    /// boyunca N terminal × frame maliyeti doğardı.
    public func attachView(for id: TerminalID, into container: NSView) {
        guard let entry = entries[id] else { return }
        // Reassert yolu (host her layout'ta çağırır): view zaten burada — no-op.
        // Frame'i host oturtur, çizim kararını da o verir (fit true → needsDisplay).
        guard entry.view.superview !== container else { return }
        entry.view.removeFromSuperview()
        // Frame'in tek otoritesi host'tur (TerminalHostContainer her setFrameSize/
        // layout'ta yeniden oturtur). autoresizing view'ı ızgara katı olmayan bir
        // boyuta esnetip aradaki her karede gereksiz cols/rows değişimi doğururdu.
        // 0×0 container'a (SwiftUI layout vermeden önceki makeNSView anı) frame
        // ATANMAZ: SwiftTerm'i sıfıra küçültmek emülatörü gereksiz resize ederdi.
        // Eski frame korunur; layout gelince host oturtur.
        entry.view.autoresizingMask = []
        container.addSubview(entry.view)
        // Gerçek attach olayı: buffer'dan tam yeniden çizim + görünürlük sinyali.
        // Frame henüz 0×0 olabilir; `updateFullScreen`'in dirty işaretlemesi model
        // tarafında kalıcıdır, host frame'i oturttuğunda içerik görünür olur.
        entry.view.needsDisplay = true
        entry.onVisibilityChange(true)
    }

    /// Fullscreen geçişi / pencere-space değişimi sonrası onarım. AppKit, native
    /// fullscreen'e girip çıkarken içerik view'ını ayrı bir space-window'a taşır;
    /// dönüşte SwiftTerm otomatik repaint etmez ve attach/detach yarışında frame
    /// bayat (hatta sıfır) kalabilir → kart bozuk/boş görünür. Bağlı her view'ın
    /// host'undan yeni bir layout geçişi istenir (frame'i host oturtur — refactor
    /// 4.5; delta varsa SwiftTerm sizeChanged → PTY resize zinciri kendiliğinden
    /// tetiklenir) ve buffer'dan tam çizim işaretlenir. Grid round-trip onarımının
    /// (attachView) fullscreen analogudur.
    public func refreshAttachedViews() {
        for entry in entries.values {
            guard let superview = entry.view.superview, !superview.bounds.isEmpty else { continue }
            // Fit host'un işidir (refactor 4.5): onarım yalnız yeni bir layout
            // geçişi ister; `TerminalHostContainer.layout()` frame'i oturtur.
            superview.needsLayout = true
            entry.view.needsDisplay = true
            // Görünürlük sinyali = foreground yüzeyi + requestRepaint (SIGWINCH);
            // needsDisplay tek başına TUI'yi yeniden çizdirmez (boş kart).
            entry.onVisibilityChange(true)
        }
    }

    /// Faz 4.4: canlı view şu an bir container'a bağlı mı.
    public func isAttached(_ id: TerminalID) -> Bool {
        entries[id]?.view.superview != nil
    }

    /// Faz 4.4: route geçişinin açık kapanışı — bağlı her view SENKRON sökülür
    /// (`detachView`'un runloop ertelemesi burada YOK: erteleme SwiftUI'nin
    /// dismantle/attach yarışına karşıdır, açık çağrıda böyle bir yarış yoktur)
    /// ve her biri için gizli-terminal politikası devreye girer. View'lar yok
    /// edilmez; emülatör durumu registry'de yaşamaya devam eder.
    public func detachAll() {
        for entry in entries.values where entry.view.superview != nil {
            entry.view.removeFromSuperview()
            entry.onVisibilityChange(false)
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
