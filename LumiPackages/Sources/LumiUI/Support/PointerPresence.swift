import AppKit
import SwiftUI

/// Fare varlığını **geometriden** doğrulayan hover sensörü (karar 59).
///
/// Kenar hover'ı (karar 44) SwiftUI `.onHover` ile kuruluydu ve üç yerde
/// yanlış cevap veriyordu:
///
/// 1. **Hiç açılmama:** şerit bir terminalin üstündeyken `TerminalEventMonitor`
///    `.mouseMoved`'ı yutuyor (`shouldConsumeHover`), SwiftUI hover'ı hiç
///    görmüyordu. DİKKAT: tracking area'lar da kurtarmaz — AppKit
///    `mouseEntered/Exited`'ı `.mouseMoved` dispatch'i SIRASINDA üretir, local
///    monitor `nil` döndürünce crossing event'i de hiç doğmaz (deneyle
///    doğrulandı). Bu yüzden tek gerçek kaynak, imleç konumunu doğrudan okuyan
///    doğrulama tik'idir; tracking area yalnız anında tepki için durur.
/// 2. **Popover açılınca kapanma:** `NSPopover` / `DropdownPanel` ayrı bir
///    pencere açar, SwiftUI "fare çıktı" der. Sensör, BU PANELDEN açılmış
///    (sahiplenilmiş) child pencerelerin içini de "içeride" sayar (karar 99);
///    başka yerden açılan popover'lar paneli açmaz.
/// 3. **Kaçan giriş/çıkış:** `mouseEntered` (overlay imlecin altında doğduğunda,
///    ör. panel gizlenir gizlenmez) ve `mouseExited` (pencere değişimi, hızlı
///    çıkış, view yeniden kurulumu) tek başına bırakılmaz; view pencerede
///    olduğu SÜRECE dönen düşük frekanslı bir doğrulama tik'i fiziksel imleç
///    konumunu okur ve iki yönü de düzeltir.
///
/// Sensör tıklama yutmaz: `hitTest` daima `nil` döner — altındaki terminal ya
/// da içerik davranışı değişmez.
struct PointerPresence: NSViewRepresentable {
    /// Varlık değişiminde çağrılır (yalnız değişimde, her tik'te değil).
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PointerPresenceView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PointerPresenceView)?.onChange = onChange
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? PointerPresenceView)?.tearDown()
    }
}

/// Sensörün **saf** kararları (test edilebilir).
///
/// Bölgenin dışı yalnız iki durumda içeride sayılır (karar 99): imleç bu
/// panelin **sahip olduğu** bir yardımcı pencerenin (popover, açılır liste)
/// üstündeyse ya da panelden başlayan bir `NSMenu` takibi sürüyorsa. Ana
/// pencereye bağlı her pencere DEĞİL — top bar'ın popover'ı paneli açmaz.
enum PointerPresenceRule {
    static func isInside(
        pointer: CGPoint,
        region: CGRect?,
        isAppActive: Bool,
        isPointerInOwnedWindow: Bool,
        isMenuHeld: Bool
    ) -> Bool {
        guard isAppActive, let region else { return false }
        return region.contains(pointer) || isPointerInOwnedWindow || isMenuHeld
    }

    /// Panelin sahip olduğu yardımcı pencereler (pencere numarası).
    ///
    /// Sahiplik sayılmaz, çıkarsanır: bir pencere ilk görüldüğü anda imleç
    /// içerideyse (panelin ya da onun sahip olduğu bir popover'ın üstünde —
    /// iç içe alt menüler böylece zincirlenir) panele aittir. Kapanan pencere
    /// `attached`'tan düştüğü için sahiplik kendiliğinden biter; azaltılması
    /// unutulabilecek bir sayaç yoktur.
    static func ownedWindows(
        attached: Set<Int>,
        previouslyAttached: Set<Int>,
        owned: Set<Int>,
        wasInside: Bool
    ) -> Set<Int> {
        let kept = owned.intersection(attached)
        guard wasInside else { return kept }
        return kept.union(attached.subtracting(previouslyAttached))
    }
}

/// Tracking area + doğrulama tik'i taşıyan sensör view'ı.
private final class PointerPresenceView: NSView {
    var onChange: ((Bool) -> Void)?

    /// Doğrulama aralığı. Tik, view pencerede olduğu sürece döner: yutulan
    /// `.mouseMoved` yüzünden crossing event'i HİÇ gelmeyebiliyor, o yüzden
    /// giriş de çıkış kadar telafiye muhtaç. Maliyet iki `CGPoint`
    /// karşılaştırması; timer yalnız auto-reveal'e uygun gizli yuva varken
    /// (overlay canlıyken) vardır.
    private static let verifyInterval: TimeInterval = 0.1

    private var isInside = false
    private var verifyTimer: Timer?
    private var menuObservers: [NSObjectProtocol] = []

    /// Bir önceki ölçümde ana pencereye bağlı olan yardımcı pencereler.
    private var previouslyAttached: Set<Int> = []
    /// Bu panelden açılmış yardımcı pencereler (`PointerPresenceRule.ownedWindows`).
    private var ownedWindows: Set<Int> = []
    /// Panelin içindeyken başlayan `NSMenu` takibi (`.contextMenu`) sürüyor mu.
    /// Menü penceresi ana pencereye bağlı olmadığı için ayrı izlenir; başlangıç
    /// ve bitiş bildirimleri AppKit tarafından çift olarak gönderilir.
    private var isMenuHeld = false

    /// Sensör tamamen şeffaftır: tıklama ve sürükleme altındaki view'a gider.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
        // Yeniden yerleşimde (şerit ↔ panel genişliği) varlık yeniden ölçülür.
        evaluate()
    }

    override func mouseEntered(with event: NSEvent) { evaluate() }

    override func mouseExited(with event: NSEvent) { evaluate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            tearDown()
        } else {
            // Sensör doğmadan önce açık olan pencereler (ör. top bar popover'ı)
            // hiçbir zaman bu panelin sayılmaz.
            previouslyAttached = attachedWindowNumbers
            startVerifying()
            evaluate()
        }
    }

    func tearDown() {
        stopVerifying()
        ownedWindows = []
        isMenuHeld = false
        if isInside {
            isInside = false
            onChange?(false)
        }
    }

    private func evaluate() {
        let attached = attachedWindowNumbers
        ownedWindows = PointerPresenceRule.ownedWindows(
            attached: attached,
            previouslyAttached: previouslyAttached,
            owned: ownedWindows,
            wasInside: isInside
        )
        previouslyAttached = attached

        let inside = PointerPresenceRule.isInside(
            pointer: NSEvent.mouseLocation,
            region: screenRegion,
            isAppActive: NSApp.isActive,
            isPointerInOwnedWindow: isPointerInOwnedWindow,
            isMenuHeld: isMenuHeld
        )
        guard inside != isInside else { return }
        isInside = inside
        onChange?(inside)
    }

    private func startVerifying() {
        guard verifyTimer == nil else { return }
        let timer = Timer(timeInterval: Self.verifyInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        // `.common`: kaydırma/sürükleme ve menü takibi sırasında da dönmeli.
        RunLoop.main.add(timer, forMode: .common)
        verifyTimer = timer
        observeMenuTracking()
    }

    private func stopVerifying() {
        verifyTimer?.invalidate()
        verifyTimer = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
    }

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isInside else { return }
                    self.isMenuHeld = true
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isMenuHeld else { return }
                    self.isMenuHeld = false
                    self.evaluate()
                }
            },
        ]
    }

    /// Bölgenin ekran koordinatındaki dikdörtgeni; pencere yoksa `nil`.
    private var screenRegion: CGRect? {
        guard let window, window.isVisible, !bounds.isEmpty else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    /// Ana pencereye (zincirleme) bağlı, görünür yardımcı pencereler.
    private var attachedWindowNumbers: Set<Int> {
        guard let window else { return [] }
        return Set(NSApp.windows.lazy
            .filter { $0 !== window && $0.isVisible && Self.isDescendant($0, of: window) }
            .map(\.windowNumber))
    }

    /// İmlecin altındaki pencere bu panelin sahip olduğu bir pencere mi?
    private var isPointerInOwnedWindow: Bool {
        guard !ownedWindows.isEmpty else { return false }
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        return ownedWindows.contains(number)
    }

    private static func isDescendant(_ candidate: NSWindow, of ancestor: NSWindow) -> Bool {
        var parent = candidate.parent
        while let current = parent {
            if current === ancestor { return true }
            parent = current.parent
        }
        return false
    }
}
