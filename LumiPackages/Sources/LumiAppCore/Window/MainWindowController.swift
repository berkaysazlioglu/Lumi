import AppKit
import LumiKit
import LumiUI

/// Ana pencerenin sahibi (design/03 §1-2, refactor 3.6).
///
/// `AppDelegate`'ten çıkarılan sorumluluklar: pencere kurulumu ve color space
/// pinlemesi, bounds restore/persist (500ms debounce, karar 9 — `frameAutosave`
/// YOK), traffic-light hizası ve focus-mode senkronu, fullscreen/resize
/// gözlemcileri, `windowShouldClose` yönlendirmesi.
@MainActor
final class MainWindowController: NSObject {
    static let defaultBoundsPersistDebounce: TimeInterval = 0.5
    static let defaultSize = NSSize(width: 1400, height: 900)
    static let minimumSize = NSSize(width: 1000, height: 600)

    private(set) var window: NSWindow?

    /// Çarpı (X) → quit-onay akışı. `true` dönerse pencere gerçekten kapanır.
    var onWindowShouldClose: (() -> Bool)?
    /// Fullscreen giriş/çıkışı sonrası terminal view'larının onarımı.
    var onFullScreenTransition: (() -> Void)?

    private let config: any ConfigServicing
    private let boundsPersistDebounce: TimeInterval
    private var pendingBoundsPersist: DispatchWorkItem?
    private var isRestoringWindow = true
    private var observerTokens: [NSObjectProtocol] = []

    init(
        config: any ConfigServicing,
        boundsPersistDebounce: TimeInterval = MainWindowController.defaultBoundsPersistDebounce
    ) {
        self.config = config
        self.boundsPersistDebounce = boundsPersistDebounce
    }

    // MARK: - Kurulum

    @discardableResult
    func install(
        contentView: NSView,
        uiState: UIState,
        screens: [NSRect] = NSScreen.screens.map(\.visibleFrame)
    ) -> NSWindow {
        let window = makeWindow()
        restoreBounds(window, uiState: uiState, screens: screens)
        window.contentView = contentView

        // Maximize flag'i show'dan ÖNCE uygulanır (flash önleme)
        if uiState.windowMaximized == true, !window.isZoomed {
            window.zoom(nil)
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window

        observeBounds(window)
        observeFullScreen(window)
        applyTrafficLightLayout()
        // İlk layout butonları sıfırlayabilir — bir sonraki runloop'ta tekrar uygula
        DispatchQueue.main.async { [weak self] in self?.applyTrafficLightLayout() }
        isRestoringWindow = false
        return window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self // windowShouldClose → quit-onay akışı
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = Self.minimumSize
        window.backgroundColor = NSColor(
            srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x12 / 255, alpha: 1
        )
        // Pencerenin color space'i açıkça pinlenmezse AppKit launch bağlamına göre
        // farklı seçiyor: paketlenmiş .app yönetilen sRGB→ekran (soluk), `swift run`
        // çıplak executable ise ekranın native gamut'una yakın (canlı) backing store
        // alıyor. `dev`deki canlı görünümü her iki build'de de elde etmek için ekranın
        // native color space'ini kullanıyoruz (P3 ekranlarda sRGB değerler daha doygun).
        window.colorSpace = NSScreen.main?.colorSpace ?? .sRGB
        return window
    }

    private func restoreBounds(_ window: NSWindow, uiState: UIState, screens: [NSRect]) {
        if let saved = uiState.windowBounds,
           let valid = WindowBoundsValidator.validated(saved, screens: screens) {
            window.setFrame(
                NSRect(x: valid.x, y: valid.y, width: valid.width, height: valid.height),
                display: false
            )
        } else {
            window.center()
        }
    }

    // MARK: - Traffic light (karar 30)

    /// `TrafficLightLayout` titlebar container'ı header yüksekliğine büyütür;
    /// tıklama alanı kırpılmaz.
    func applyTrafficLightLayout() {
        guard let window else { return }
        TrafficLightLayout.apply(to: window)
    }

    /// Focus mode: chrome gizlenirken traffic light'lar da gizlenir (design/03 §2).
    func setTrafficLightsHidden(_ hidden: Bool) {
        guard let window else { return }
        TrafficLightLayout.setHidden(hidden, in: window)
    }

    // MARK: - Gözlemciler

    private func observeFullScreen(_ window: NSWindow) {
        observe(
            [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification],
            object: window
        ) { [weak self] in
            self?.applyTrafficLightLayout()
            self?.onFullScreenTransition?()
        }
    }

    /// Bounds persistence: 500ms debounce; zoom'dayken bounds yazılmaz (karar 9).
    private func observeBounds(_ window: NSWindow) {
        observe(
            [NSWindow.didMoveNotification, NSWindow.didResizeNotification],
            object: window
        ) { [weak self] in
            self?.scheduleBoundsPersist()
            self?.applyTrafficLightLayout() // resize titlebar layout'unu sıfırlar
        }
    }

    private func observe(
        _ names: [Notification.Name],
        object: AnyObject?,
        handler: @escaping @MainActor () -> Void
    ) {
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: object, queue: .main
            ) { _ in
                MainActor.assumeIsolated { handler() }
            }
            observerTokens.append(token)
        }
    }

    func scheduleBoundsPersist() {
        guard !isRestoringWindow, let window else { return }
        pendingBoundsPersist?.cancel()
        let isZoomed = window.isZoomed
        let frame = window.frame
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.config.updateUIState { state in
                    state.windowMaximized = isZoomed
                    if !isZoomed {
                        state.windowBounds = WindowBounds(
                            x: frame.origin.x,
                            y: frame.origin.y,
                            width: frame.width,
                            height: frame.height
                        )
                    }
                }
            }
        }
        pendingBoundsPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + boundsPersistDebounce, execute: work)
    }

    /// Kapanış simetrisi: gözlemci token'ları bırakılır, bekleyen yazım iptal edilir.
    func stop() {
        pendingBoundsPersist?.cancel()
        pendingBoundsPersist = nil
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    /// Çarpı (X) pencereyi DOĞRUDAN kapatmaz. Pencere önce kapansaydı quit-onay
    /// dialogu (SwiftUI, pencere içeriğinde) görünmez kalır ve `.terminateLater`
    /// cevapsız asılırdı — app penceresiz halde Dock'ta takılırdı. Kapatma isteği
    /// Cmd+Q ile aynı `applicationShouldTerminate` akışına yönlendirilir; pencere
    /// yalnız uygulama gerçekten çıkarken kapanır (design/03 §2).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onWindowShouldClose?() ?? true
    }
}
