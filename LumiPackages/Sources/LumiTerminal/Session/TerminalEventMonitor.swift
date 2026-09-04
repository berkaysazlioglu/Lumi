import AppKit

/// Terminal alt sisteminin **tek** uygulama-seviyesi `NSEvent` monitörü (refactor 4.7).
///
/// Önceden üç ayrı kayıt vardı: `TerminalSessionManager` init'inde global keyDown ve
/// leftMouseDown monitörleri, ayrıca `DropAwareTerminalView` başına bir scrollWheel/
/// mouseMoved monitörü (N terminal → N+2 kayıt, her event N closure). Artık tek kayıt
/// var; hangi terminale ait olduğu **hit-test** ile çözülür.
///
/// Hit-test iki işi birden yapar:
/// 1. Doğru terminali seçer (üst üste binen kartlarda "ilk bounds tutan" hatası biter).
/// 2. Terminalin üstünde tam-ekran bir overlay (Settings/FileViewer) varsa hit sonucu
///    overlay olur, terminal bulunamaz ve event **yutulmadan** geçer — bu, eski
///    `TerminalInputGate.shared` global bayrağının yerini alır (refactor 4.6): kapıyı
///    elle sürmek (RootView `.onChange`) gerekmez, yeni overlay eklendiğinde
///    "tek satır eklemeyi unutma" riski yapısal olarak yoktur.
///
/// `NSEvent` async sınırdan geçirilmez: her event senkron işlenir; yalnız odak
/// çözümlemesi bir runloop turu ertelenir (first responder tıklama dispatch'inden
/// SONRA değişir) ve o turda da event değil, MainActor'a bağlı zayıf pencere
/// referansı okunur.
@MainActor
public final class TerminalEventMonitor {
    /// Klavye (doğal düzenleme eşlemesi), sol tık (kart odağı), tekerlek + hover
    /// (alt-buffer scroll köprüsü).
    private static let eventMask: NSEvent.EventTypeMask = [
        .keyDown, .leftMouseDown, .scrollWheel, .mouseMoved,
    ]

    /// AppKit monitörü kurulduğunda tutar; yalnız `removeMonitor` bırakır.
    private var monitor: Any?
    private var onViewFocused: ((NSView) -> Void)?
    /// leftMouseDown'ın penceresi: first responder ancak dispatch sonrası değişir.
    private weak var pendingFocusWindow: NSWindow?

    public init() {}

    public var isRunning: Bool { monitor != nil }

    /// Idempotent: zaten kuruluysa hiçbir şey yapmaz.
    public func start(onViewFocused: @escaping (NSView) -> Void) {
        guard monitor == nil else { return }
        self.onViewFocused = onViewFocused
        monitor = NSEvent.addLocalMonitorForEvents(matching: Self.eventMask) { [weak self] event in
            // AppKit local monitörleri main'de çağırır; synthetic event enjeksiyonu
            // edge case'ine karşı sigorta — trap'lemek yerine event'i geçir.
            guard Thread.isMainThread else { return event }
            // NSEvent Sendable değil: isolation sınırından yalnız Bool taşınır.
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Idempotent: kurulu değilse hiçbir şey yapmaz.
    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onViewFocused = nil
        pendingFocusWindow = nil
    }

    // MARK: - Yönlendirme

    /// `true` → event yutuldu (AppKit dağıtmaz); `false` → normal dağıtım sürsün.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            return routeKeyDown(event)
        case .leftMouseDown:
            noteFocusClick(in: event.window)
            return false
        case .scrollWheel, .mouseMoved:
            let isScroll = event.type == .scrollWheel
            return routePointer(
                isScroll: isScroll,
                locationInWindow: event.locationInWindow,
                in: event.window,
                deltaY: isScroll ? event.scrollingDeltaY : 0,
                isPrecise: isScroll && event.hasPreciseScrollingDeltas
            )
        default:
            return false
        }
    }

    /// SwiftTerm `keyDown` sealed olduğundan doğal-düzenleme eşlemeleri
    /// (Option+Backspace → ^W vb.) dispatch'ten önce burada uygulanır. Yalnız first
    /// responder bir Lumi terminal view'ıyken devreye girer. `true` → event yutuldu.
    func routeKeyDown(_ event: NSEvent) -> Bool {
        guard let view = event.window?.firstResponder as? DropAwareTerminalView,
              let bytes = NaturalEditingKeyMap.bytes(for: event) else {
            return false
        }
        view.send(bytes)
        return true
    }

    /// Tekerlek/hover yönlendirmesi. `true` → event yutuldu (SwiftTerm görmez).
    /// NSEvent'siz imza: testler kararı doğrudan sürebilir.
    @discardableResult
    func routePointer(
        isScroll: Bool,
        locationInWindow: NSPoint,
        in window: NSWindow?,
        deltaY: CGFloat = 0,
        isPrecise: Bool = false
    ) -> Bool {
        guard let window, let view = Self.terminalView(at: locationInWindow, in: window) else {
            return false
        }
        guard isScroll else { return view.shouldConsumeHover() }
        return view.consumeScroll(deltaY: deltaY, isPrecise: isPrecise, locationInWindow: locationInWindow)
    }

    /// Karta tıklama → `TerminalEvent.viewFocused` (Electron `setActiveTerminal`
    /// paritesi). First responder tıklama dispatch'inden SONRA değiştiği için
    /// çözümleme bir runloop turu ertelenir.
    func noteFocusClick(in window: NSWindow?) {
        pendingFocusWindow = window
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let window = self.pendingFocusWindow
                self.pendingFocusWindow = nil
                guard let view = window?.firstResponder as? DropAwareTerminalView else { return }
                self.onViewFocused?(view)
            }
        }
    }

    /// Pencere koordinatındaki noktanın altındaki terminal view'ı — hit sonucundan
    /// yukarı yürünür (SwiftTerm kendi alt view'larını, örn. gizli `NSScroller`,
    /// ekler). Üstte bir overlay varsa zincirde terminal bulunmaz → `nil`.
    static func terminalView(at locationInWindow: NSPoint, in window: NSWindow) -> DropAwareTerminalView? {
        var candidate = window.contentView?.hitTest(locationInWindow)
        while let view = candidate {
            if let terminal = view as? DropAwareTerminalView { return terminal }
            candidate = view.superview
        }
        return nil
    }
}
