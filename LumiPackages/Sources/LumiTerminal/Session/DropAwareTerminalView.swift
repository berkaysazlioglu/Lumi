import AppKit
import LumiKit
import SwiftTerm

/// Dosya sürükle-bırak destekli terminal view'ı .
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
        // gösteriyordu. iTerm2 "thin strokes" karşılığı. Sabit davranış —
        // kullanıcı ayarı yok (karar 29).
        fontSmoothing = false
        // Mouse raporlama AÇIK kalır (SwiftTerm default'u, v1/xterm.js paritesi):
        // tıklama SGR press/release olarak TUI'ye gider — Claude input box'ında
        // caret tıklanan yere konur. Hover'ın buglu "release" raporu ise monitor'da
        // ayrıca bastırılır (aşağıda — SwiftTerm encodeButton release=3 bug'ı).
        TerminalTheme.lumi.apply(to: self)
        // Karar 116: hover altı çizgisi Lumi'nindir (`linkUnderline`) — SwiftTerm
        // kendi regex'inin aralığını çizer ve diske soramaz. Bu mod SwiftTerm'in
        // hover vurgusunu ve düz tıkta linki kendisinin açmasını kapatır; yalnız
        // ⌘ basılıyken OSC 8 hücrelerinin altını çizer.
        linkHighlightMode = .alwaysWithModifier
        linkUnderline.frame = bounds
        linkUnderline.autoresizingMask = [.width, .height]
        addSubview(linkUnderline)
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

    /// İnaktif pencerede ilk tık: normalde macOS bu tıkı YALNIZ pencere
    /// aktivasyonu için yutar, view'a iletmez. Bu yüzden başka app focusluyken
    /// ikinci bir terminale tıklamak önce Lumi'yi öne getirir ama odağı geçirmez —
    /// kullanıcı iki kez tıklamak zorunda kalırdı (first responder değişmediği için
    /// `TerminalSessionManager` focus monitor'u eski terminali okur). `true`
    /// döndürünce aktivasyon tıkı aynı anda terminale de ulaşır: bu view first
    /// responder olur ve odak tek tıkta doğru terminale geçer.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideScroller()
        observeFocusLoss()
        if window == nil {
            scrollRedrawTask?.cancel()
            scrollRedrawTask = nil
            // Pencereden kopan view'da mouseUp gelmeyebilir; bekleyen link
            // jesti ve fare raporu bekletmesi açıkta kalmasın (karar 57).
            cancelLinkGesture()
        }
    }

    /// Fare basılıyken ⌘-Tab / Mission Control / menü açılması `mouseUp`'ı
    /// düşürebilir; o hâlde bekletme açık kalıp o terminale giden TÜM fare
    /// raporlarını yutardı. Odak kaybında jest iptal edilir (karar 57).
    private func observeFocusLoss() {
        focusLossObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusLossObservers = []
        // Pencereden koparken kayıtlar bırakılır (registry view'ı superview'dan
        // aldığında burası nil pencereyle çağrılır) — sızıntı kalmaz.
        guard let window else { return }
        let center = NotificationCenter.default
        // `@Sendable` şart: kayıt sırasında closure izolasyon sınırını geçiyor.
        // `self` sınırın ÖTESİNE geçmez — kuyruk `.main` olduğu için gövde
        // MainActor'da koşar ve view'a orada dokunulur.
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelLinkGesture() }
        }
        focusLossObservers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: handler
        ))
        focusLossObservers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: handler
        ))
    }


    // MARK: - Link jestleri (karar 57)

    /// Link/path tıklaması karara bağlandı: (ham link, jest, kabuk koordinatında
    /// tık noktası). Yalnız jest geçerliyse (sürüklenmediyse, seçim yokken)
    /// çağrılır.
    var onLinkActivation: ((String, TerminalLinkGesture, CGPoint) -> Void)?
    /// Düz tık bir link üstünde başladı: bu tıkın fare raporları PTY'ye
    /// GİTMEDEN bekletilmeli (`true` → bekletme başladı).
    var onLinkGestureBegan: (() -> Void)?
    /// Jest bitti. `claimed == true` ise bekleyen fare raporları düşürülür
    /// (Claude tıkı hiç görmez), değilse olduğu gibi akar.
    var onLinkGestureEnded: ((_ claimed: Bool) -> Void)?

    /// Karar 57: düz tıkla açılan eylem popover'ı. Kapalıyken düz tık terminale
    /// aittir; ⌘ / ⇧⌘ doğrudan açma her hâlde çalışır.
    var isLinkActionsEnabled = true {
        didSet {
            guard isLinkActionsEnabled != oldValue else { return }
            clearLinkHover()
        }
    }

    /// Göreli yolların çözüldüğü dizin (terminalin açıldığı dizin) — hover'da
    /// diske sorulan mutlak yol buradan türer (karar 116).
    var linkBaseDirectory = ""
    var linkHomeDirectory = NSHomeDirectory()
    /// Yol adaylarının diskte olup olmadığı; testler satır içi bir fake verir.
    var linkPathCache = TerminalLinkPathCache()
    let linkUnderline = TerminalLinkUnderlineView()
    /// Hover durumu (`DropAwareTerminalView+Links`).
    var linkHover = TerminalLinkHoverState()

    private var linkGesture = TerminalLinkGestureTracker()
    private var focusLossObservers: [any NSObjectProtocol] = []
    /// `.actions` jestinde `super.mouseDown` çağrıldığı için SwiftTerm seçim/
    /// rapor akışı normal işler; raporlar oturumda bekletilir.
    private var isDeferringMouseReports = false

    override func mouseDown(with event: NSEvent) {
        cancelLinkGesture()
        guard let gesture = Self.gesture(for: event), isAllowed(gesture) else {
            super.mouseDown(with: event)
            return
        }
        switch gesture {
        case .actions:
            // Link araması mouseUp'a ERTELENİR: düz tıkın büyük çoğunluğu bir
            // linkin üstünde değildir ve Ghostty regex'i her tıkta koşarsa
            // (satır birleştirmeli, scrollback boyu) main thread'e biner.
            beginGesture(link: nil, gesture: gesture, event: event)
            // Seçim/odak davranışı korunur; PTY'ye giden rapor bekletilir ve
            // jest bir linke dönüşmezse mouseUp'ta olduğu gibi akar.
            super.mouseDown(with: event)
        case .primary, .alternate:
            guard let link = link(at: event) else {
                super.mouseDown(with: event)
                return
            }
            // Doğrudan aktivasyon: tık ne TUI'ye gider ne seçimi bozar.
            beginGesture(link: link, gesture: gesture, event: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let gesture = linkGesture.activeGesture
        linkGesture.noteDrag(to: event.locationInWindow)
        // Sürükleme jesti iptal eder; bekletilen raporlar mouseUp'ı BEKLEMEDEN
        // akar, yoksa fare raporlayan bir TUI sürüklemeyi canlı göremezdi.
        if linkGesture.isCancelledByDrag { finishDeferredReports(claimed: false) }
        guard gesture == .primary || gesture == .alternate else {
            super.mouseDragged(with: event)
            return
        }
        // Doğrudan aktivasyon jestinde mouseDown yutulmuştu; sürükleme de yutulur.
    }

    override func mouseUp(with event: NSEvent) {
        let gesture = linkGesture.activeGesture
        if gesture == nil || gesture == .actions {
            super.mouseUp(with: event)
        }
        linkGesture.noteDrag(to: event.locationInWindow)
        guard let resolved = linkGesture.finish(hasSelection: selectionActive) else {
            finishDeferredReports(claimed: false)
            return
        }
        // Ertelenen arama: `.actions` jestinde link ancak burada çözülür.
        guard let link = resolved.link ?? self.link(at: event) else {
            finishDeferredReports(claimed: false)
            return
        }
        finishDeferredReports(claimed: true)
        onLinkActivation?(link, resolved.gesture, shellAnchor(for: event))
    }

    /// Düz sol tık her terminalde link yoluna girer (Orca paritesi, kullanıcı
    /// düzeltmesi: "orcada sol tık yetiyormuş"). Fare raporlayan bir TUI
    /// çalışıyorsa tıkın raporu bekletilir; linke denk gelmediyse olduğu gibi
    /// akar, yani link DIŞINDAKİ metinde caret koyma bozulmaz.
    private func isAllowed(_ gesture: TerminalLinkGesture) -> Bool {
        guard gesture == .actions else { return true }
        return isLinkActionsEnabled
    }

    private func beginGesture(link: String?, gesture: TerminalLinkGesture, event: NSEvent) {
        linkGesture.begin(
            link: link,
            gesture: gesture,
            origin: event.locationInWindow,
            hadSelection: selectionActive
        )
        // Bekletme mouseDown'da kurulur: tıkın linke denk gelip gelmediği ancak
        // mouseUp'ta bilinir, rapor ise basar basmaz üretilir.
        if gesture == .actions { beginDeferredReports() }
    }

    private func cancelLinkGesture() {
        linkGesture.cancel()
        finishDeferredReports(claimed: false)
    }

    private func beginDeferredReports() {
        guard !isDeferringMouseReports else { return }
        isDeferringMouseReports = true
        onLinkGestureBegan?()
    }

    private func finishDeferredReports(claimed: Bool) {
        guard isDeferringMouseReports else { return }
        isDeferringMouseReports = false
        onLinkGestureEnded?(claimed)
    }

    static func gesture(for event: NSEvent) -> TerminalLinkGesture? {
        let flags = event.modifierFlags
        return TerminalLinkGesture.resolve(
            isLeftButton: event.type == .leftMouseDown || event.type == .leftMouseUp,
            clickCount: event.clickCount,
            modifiers: .init(
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control)
            )
        )
    }

    /// Tık hücresindeki link metni (karar 116 — `DropAwareTerminalView+Links`).
    private func link(at event: NSEvent) -> String? {
        linkText(atCell: cell(atWindowPoint: event.locationInWindow))
    }

    func cell(atWindowPoint point: NSPoint) -> TerminalLinkHitTest.Cell {
        let terminal = getTerminal()
        // Hücre boyutu SwiftTerm'in kendi `cellDimension`'ından türer (`cellSize`);
        // `bounds/rows` kesirli hücrelerde kenarlarda bir satır kayabiliyordu.
        return TerminalLinkHitTest.gridCell(
            forViewPoint: convert(point, from: nil),
            cellSize: cellSize,
            bounds: bounds,
            cols: terminal.cols,
            rows: terminal.rows,
            isFlipped: isFlipped
        )
    }

    private func shellAnchor(for event: NSEvent) -> CGPoint {
        TerminalLinkAnchor.shellPoint(
            windowPoint: event.locationInWindow,
            contentHeight: window?.contentView?.bounds.height ?? bounds.height
        )
    }

    // MARK: - Mouse: hover-caret bastırma + wheel scroll (v1 / xterm.js paritesi)

    // SwiftTerm'in `scrollWheel`'i ve `mouseMoved`'ı `public` (open değil); modül
    // dışından override edilemez. Event'ler SwiftTerm'e ulaşmadan `TerminalEventMonitor`
    // (uygulama-seviyesi TEK local monitor) tarafından yakalanır ve hit-test ile bu
    // view'a yönlendirilir; burada yalnız terminale ÖZGÜ durum (birikim, redraw
    // debounce) yaşar. Pin'li revision'da (24a68bc) scrollWheel alt-buffer'ı kendisi
    // de ele alıyor (mouse-mode'da wheel forwarding, mouse-off'ta yön tuşu); yine de
    // araya girmemizin gerekçeleri:
    // 1. mouseMoved upstream bug'ı: hover'ı "sol buton release" (`ESC[<32;x;ym`)
    //    olarak kodlar (encodeButton release=3 +32) ve allowMouseReporting'i atlar
    //    — Claude tıklama sanıp caret'i taşır. anyEvent modunda hover'ı yutarız.
    // 2. Trackpad: SwiftTerm event.deltaY ile event başına sabit adım üretir
    //    (precise piksel delta'sını ve momentum'u tanımaz) — WheelStepAccumulator
    //    hücre-yüksekliği birimli birikimli çeviri yapar.
    // Event'i yuttuğumuz için upstream yoluyla çifte gönderim oluşmaz.

    /// Trackpad piksel-delta'larını adıma çeviren birikimli durum (terminal başına).
    private var wheelAccumulator = WheelStepAccumulator()

    /// Hover (mouseMoved): anyEvent (1003) modunda SwiftTerm hover'ı SGR "sol buton
    /// release" olarak KODLAYIP yollar (upstream bug: encodeButton release=3 →
    /// `ESC[<32;x;ym`) — Claude bunu tıklama sayıp caret'i taşır. Bu modda event
    /// AppKit'e bırakılmaz; altı çizgi Lumi'nin olduğu için (karar 116) SwiftTerm'e
    /// yeniden oynatılması da gerekmez. `true` → event yutuldu.
    func shouldConsumeHover() -> Bool {
        getTerminal().mouseMode == .anyEvent
    }

    /// Tekerlek/trackpad delta'sı. `true` → event yutuldu (SwiftTerm görmez).
    func consumeScroll(deltaY: CGFloat, isPrecise: Bool, locationInWindow: NSPoint) -> Bool {
        // Kaydırma içeriği hover çizgisinin altından kaydırır; bir sonraki
        // hover yeniden arar.
        invalidateLinkHover()
        return handleScroll(
            deltaY: deltaY,
            isPrecise: isPrecise,
            viewPoint: convert(locationInWindow, from: nil),
            terminal: getTerminal()
        )
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

// MARK: - Izgara geometrisi (host ortalaması)

extension DropAwareTerminalView: TerminalGridSizing {
    /// SwiftTerm hücre boyutunu (`cellDimension`) dışarı açmaz; `getOptimalFrameSize()`
    /// = hücre × güncel satır/sütun (+ scroller genişliği) üzerinden geri türetilir.
    /// Scroller `hideScroller()` ile kalıcı gizli olduğundan o terim 0'dır — scroller
    /// tekrar görünür yapılırsa bu hesap gözden geçirilmeli.
    /// Host bununla ızgarayı container içinde ortalar — bkz. `TerminalGridFit`.
    var cellSize: CGSize {
        let terminal = getTerminal()
        let optimal = getOptimalFrameSize().size
        let cols = CGFloat(max(1, terminal.cols))
        let rows = CGFloat(max(1, terminal.rows))
        return CGSize(width: optimal.width / cols, height: optimal.height / rows)
    }
}
