import AppKit
import SwiftTerm

/// Dosya sürükle-bırak destekli terminal view'ı (spec/20 §drag-drop).
/// SwiftTerm drop'u kendisi işlemez; Electron'daki app-seviyesi davranışın
/// karşılığıdır: bırakılan dosyaların path'i terminale girdi olarak yazılır.
final class DropAwareTerminalView: TerminalView {
    /// Main thread'de çağrılır; path'ler quote'lanmamış ham halleriyle gelir.
    var onFileDrop: (([String]) -> Void)?

    override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        configureLumiDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLumiDefaults()
    }

    private func configureLumiDefaults() {
        registerForDraggedTypes([.fileURL])
        // macOS konvansiyonu (Terminal.app): Option meta DEĞİLDİR — Option'lı
        // tuşlar birleşik karakter üretir (TR klavyede [ ] { } vb. Option ister).
        // SwiftTerm default'u true'dur ve bu karakterleri ESC+harf'e çevirirdi.
        optionAsMetaKey = false
        // SwiftTerm'in desteklemediği modlar (örn. DECSET 2031 renk-şeması
        // bildirimi — Claude Code probe'lar, desteklenmemesi zararsız) konsola
        // "Info: Unhandled..." satırları basıyordu; debug log'u sustur.
        getTerminal().silentLog = true
        // v1 tipografi paritesi: Electron tarafı `-webkit-font-smoothing:
        // antialiased` ile macOS stem-darkening'i kapatıyordu; SwiftTerm
        // default'u (true) aynı glyph'leri daha kalın/parlak ("bold/glow")
        // gösteriyordu. iTerm2 "thin strokes" karşılığı. Config default'u
        // (AppConfig.terminalFontSmoothing=false) ile aynı; kullanıcı
        // Settings'ten değiştirirse TerminalSession.setFontSmoothing ezer.
        fontSmoothing = false
        // Mouse raporlama AÇIK kalır (SwiftTerm default'u, v1/xterm.js paritesi):
        // tıklama SGR press/release olarak TUI'ye gider — Claude input box'ında
        // caret tıklanan yere konur. Hover'ın buglu "release" raporu ise monitor'da
        // ayrıca bastırılır (aşağıda — SwiftTerm encodeButton release=3 bug'ı).
        TerminalTheme.apply(to: self)
        hideScroller()
    }

    /// SwiftTerm her zaman bir NSScroller subview'i ekler ve gizleme API'si sunmaz.
    /// v1 paritesi: kaydırma çubuğu görünmez (fare tekeriyle scroll çalışmaya devam
    /// eder — scroller yalnız görsel göstergedir). isHidden kalıcıdır; SwiftTerm
    /// hiçbir yerde tekrar göstermez. viewDidMoveToWindow'da da garanti edilir.
    private func hideScroller() {
        for case let scroller as NSScroller in subviews {
            scroller.isHidden = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideScroller()
        if window == nil {
            removeEventMonitor()
            scrollRedrawTask?.cancel()
            scrollRedrawTask = nil
        } else {
            installEventMonitor()
        }
    }

    // MARK: - Mouse: hover-caret bastırma + wheel scroll (v1 / xterm.js paritesi)

    /// SwiftTerm'in `scrollWheel`'i ve `mouseMoved`'ı `public` (open değil); modül
    /// dışından override edilemez. Event'ler SwiftTerm'e ulaşmadan local monitor ile
    /// yakalanır. Pin'li revision'da (24a68bc) scrollWheel alt-buffer'ı kendisi de
    /// ele alıyor (mouse-mode'da wheel forwarding, mouse-off'ta yön tuşu); yine de
    /// araya girmemizin gerekçeleri:
    /// 1. mouseMoved upstream bug'ı: hover'ı "sol buton release" (`ESC[<32;x;ym`)
    ///    olarak kodlar (encodeButton release=3 +32) ve allowMouseReporting'i atlar
    ///    — Claude tıklama sanıp caret'i taşır. anyEvent modunda hover'ı yutarız.
    /// 2. Trackpad: SwiftTerm event.deltaY ile event başına sabit adım üretir
    ///    (precise piksel delta'sını ve momentum'u tanımaz) — WheelStepAccumulator
    ///    hücre-yüksekliği birimli birikimli çeviri yapar.
    /// Event'i yuttuğumuz için upstream yoluyla çifte gönderim oluşmaz.
    private var eventMonitor: Any?

    /// Trackpad piksel-delta'larını adıma çeviren birikimli durum (terminal başına).
    private var wheelAccumulator = WheelStepAccumulator()

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        // NSEvent Sendable değil; monitor closure'u non-isolated. Yalnız Sendable
        // skalerleri çıkarıp MainActor işine taşıyoruz (event/window referansı geçirmeden).
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved]) { [weak self] event in
            // AppKit local monitor'ları main'de çağırır; synthetic event enjeksiyonu
            // edge case'ine karşı sigorta — assumeIsolated trap'lemesin, event geçsin.
            guard Thread.isMainThread else { return event }
            let isScroll = event.type == .scrollWheel
            let deltaY = isScroll ? event.scrollingDeltaY : 0
            let isPrecise = isScroll && event.hasPreciseScrollingDeltas
            let location = event.locationInWindow
            let windowID = event.window.map(ObjectIdentifier.init)
            let consumed = MainActor.assumeIsolated {
                self?.handleMonitoredEvent(
                    isScroll: isScroll, deltaY: deltaY, isPrecise: isPrecise,
                    locationInWindow: location, windowID: windowID
                ) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// true → event yutuldu (SwiftTerm görmez). false → SwiftTerm normal işlesin.
    private func handleMonitoredEvent(
        isScroll: Bool, deltaY: CGFloat, isPrecise: Bool,
        locationInWindow: NSPoint, windowID: ObjectIdentifier?
    ) -> Bool {
        guard let window, ObjectIdentifier(window) == windowID else { return false }
        let viewPoint = convert(locationInWindow, from: nil)
        guard bounds.contains(viewPoint) else { return false }
        let terminal = getTerminal()
        guard isScroll else {
            // Hover (mouseMoved): anyEvent (1003) modunda SwiftTerm hover'ı SGR
            // "sol buton release" olarak KODLAYIP yollar (upstream bug: encodeButton
            // release=3 → `ESC[<32;x;ym`) — Claude bunu tıklama sayıp caret'i taşır.
            // Bu modda yut; diğer modlarda SwiftTerm'e bırak.
            // Bilinçli trade-off: anyEvent aktifken (Claude hep açar) Cmd+hover link
            // önizlemesi de çalışmaz — geçirsek hover her seferinde caret'i taşırdı.
            return terminal.mouseMode == .anyEvent
        }
        return handleScroll(deltaY: deltaY, isPrecise: isPrecise, viewPoint: viewPoint, terminal: terminal)
    }

    /// Alt-buffer'da wheel → uygulamanın beklediği sinyale çevrilir; normal buffer'da
    /// SwiftTerm'in kendi scrollback kaydırması kullanılsın diye false döner.
    private func handleScroll(deltaY: CGFloat, isPrecise: Bool, viewPoint: NSPoint, terminal: Terminal) -> Bool {
        guard deltaY != 0 else { return false }
        guard terminal.isCurrentBufferAlternate else { return false }
        // Precise (trackpad): piksel delta'sı hücre yüksekliğiyle adıma çevrilir.
        // Klasik tekerlek: delta zaten satır cinsindendir (unit=1).
        let cellHeight = bounds.height / CGFloat(max(1, terminal.rows))
        let unit = isPrecise ? max(1, cellHeight) : 1
        let steps = wheelAccumulator.consume(delta: deltaY, unit: unit)
        // Adım üretilmese de event yutulur: birikim sürer, momentum akışı doğal
        // hızda adım üretir; SwiftTerm'e bırakmak çifte gönderim yaratırdı.
        guard steps != 0 else { return true }
        let isUp = steps > 0
        if terminal.mouseMode != .off {
            // Mouse mode'daki TUI'ye (Claude: 1000/1002/1003+1006, PTY probe ile
            // doğrulandı) wheel event'i gönder; uygulama kendi geçmişini kaydırır.
            // encodeButton+sendEvent terminalin pazarlık ettiği protokole göre
            // kodlar (SGR/X10/urxvt/UTF8) — elle SGR kurmak 1006'sız TUI'leri kırardı.
            let cell = MouseWheelGeometry.gridCell(
                forViewPoint: viewPoint, bounds: bounds,
                cols: terminal.cols, rows: terminal.rows, isFlipped: isFlipped
            )
            // Wheel butonları (xterm): 4 = yukarı, 5 = aşağı; sendEvent 0-tabanlı alır.
            let flags = terminal.encodeButton(
                button: isUp ? 4 : 5, release: false, shift: false, meta: false, control: false
            )
            for _ in 0 ..< abs(steps) {
                terminal.sendEvent(buttonFlags: flags, x: cell.col - 1, y: cell.row - 1)
            }
        } else {
            // Mouse'suz pager (less/vim): yön tuşu.
            let sequence = isUp
                ? (terminal.applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
                : (terminal.applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
            for _ in 0 ..< abs(steps) { send(sequence) }
        }
        scheduleScrollRedraw()
        return true
    }

    // MARK: - Scroll sonrası tam yeniden çizim (SwiftTerm kısmi-çizim artıkları)

    /// Defense-in-depth: bayat satırların KÖK nedenleri pin'li SwiftTerm revision'ında
    /// düzeltildi (94b6356 CSI T, 9446f60/468d0a8 2026 render) — bu katman, scroll
    /// burst'lerindeki kalan/gelecek dirty-rect aksamalarına karşı ucuz güvenlik ağıdır
    /// (requestRepaint ile aynı bilinen desen: "needsDisplay tek başına yetmiyor").
    /// updateFullScreen (tüm hücreler dirty) + setNeedsDisplay(bounds).
    /// İki aşamalı tetik: son adımdan 150ms sonra (burst bitişi) + 450ms'te bir kez
    /// daha — TUI'nin PTY round-trip'iyle geciken son karesini de yakalar. Sürekli
    /// scroll'da en geç 250ms'te bir ara tam çizim yapılır (bayatlık birikmesin).
    /// Üretimde artıksız doğrulanırsa kaldırılabilir; debounce'lu olduğundan maliyeti düşük.
    private static let scrollRedrawTrailing: Duration = .milliseconds(150)
    private static let scrollRedrawLate: Duration = .milliseconds(300)
    private static let scrollRedrawMaxLatencyNanos: UInt64 = 250_000_000

    private var scrollRedrawTask: Task<Void, Never>?
    private var lastScrollRedraw = DispatchTime.now()

    private func scheduleScrollRedraw() {
        // Sürdürülen burst: aradan maxLatency geçtiyse hemen bir tam çizim.
        if DispatchTime.now().uptimeNanoseconds - lastScrollRedraw.uptimeNanoseconds
            > Self.scrollRedrawMaxLatencyNanos {
            performScrollRedraw()
        }
        scrollRedrawTask?.cancel()
        scrollRedrawTask = Task { @MainActor in
            try? await Task.sleep(for: Self.scrollRedrawTrailing)
            guard !Task.isCancelled else { return }
            performScrollRedraw()
            try? await Task.sleep(for: Self.scrollRedrawLate)
            guard !Task.isCancelled else { return }
            performScrollRedraw()
        }
    }

    private func performScrollRedraw() {
        lastScrollRedraw = DispatchTime.now()
        getTerminal().updateFullScreen()
        setNeedsDisplay(bounds)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls.map(\.path))
        return true
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }
}
