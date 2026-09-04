import AppKit
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiAppCore

/// `MainWindowController` (refactor 3.6): pencere kurulumu ve bounds
/// persistence'ı `AppDelegate`'ten çıkınca test edilebilir hale geldi.
/// Headless testte NSWindow kurulabiliyor (`TerminalSessionReattachTests`
/// deseni).
@MainActor
final class MainWindowControllerTests: XCTestCase {
    private static let testDebounce: TimeInterval = 0.02
    private static let screens = [NSRect(x: 0, y: 0, width: 2000, height: 1400)]

    private func makeController(_ config: FakeConfigService) -> MainWindowController {
        MainWindowController(config: config, boundsPersistDebounce: Self.testDebounce)
    }

    private func install(
        _ controller: MainWindowController,
        uiState: UIState = .defaults
    ) -> NSWindow {
        controller.install(
            contentView: NSView(),
            uiState: uiState,
            screens: Self.screens
        )
    }

    // MARK: - Kurulum

    func testWindowUsesDesignedStyleAndMinimumSize() {
        let controller = makeController(FakeConfigService())
        defer { controller.stop() }

        let window = install(controller)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.minSize, MainWindowController.minimumSize)
        XCTAssertTrue(window.delegate === controller)
    }

    /// Karar 9: bounds `ui-state.json`'dan restore edilir (frameAutosave YOK).
    func testSavedBoundsAreRestoredWhenValid() {
        let controller = makeController(FakeConfigService())
        defer { controller.stop() }
        var state = UIState.defaults
        state.windowBounds = WindowBounds(x: 120, y: 90, width: 1200, height: 800)

        let window = install(controller, uiState: state)

        XCTAssertEqual(window.frame, NSRect(x: 120, y: 90, width: 1200, height: 800))
    }

    /// Ekran dışına düşen kayıt reddedilir; pencere default boyutta ortalanır.
    func testOffScreenBoundsFallBackToDefaultSize() {
        let controller = makeController(FakeConfigService())
        defer { controller.stop() }
        var state = UIState.defaults
        state.windowBounds = WindowBounds(x: 90_000, y: 90_000, width: 1200, height: 800)

        let window = install(controller, uiState: state)

        XCTAssertEqual(window.frame.size, MainWindowController.defaultSize)
    }

    // MARK: - Bounds persistence (500ms debounce)

    func testBoundsPersistIsDebouncedIntoASingleWrite() async {
        let config = FakeConfigService()
        let controller = makeController(config)
        defer { controller.stop() }
        let window = install(controller)
        let before = await config.uiStateUpdateCount

        window.setFrame(NSRect(x: 10, y: 20, width: 1100, height: 700), display: false)
        controller.scheduleBoundsPersist()
        controller.scheduleBoundsPersist()
        controller.scheduleBoundsPersist()

        try? await Task.sleep(for: .milliseconds(120))
        let writes = await config.uiStateUpdateCount - before
        XCTAssertEqual(writes, 1, "üç tetikleme tek yazıma çökmeli")

        let saved = await config.uiState().windowBounds
        XCTAssertEqual(saved?.width, 1100)
        XCTAssertEqual(saved?.height, 700)
    }

    /// Debounce penceresi dolmadan hiçbir şey yazılmaz.
    func testNothingIsPersistedBeforeTheDebounceElapses() async {
        let config = FakeConfigService()
        let controller = makeController(config)
        defer { controller.stop() }
        _ = install(controller)
        let before = await config.uiStateUpdateCount

        controller.scheduleBoundsPersist()

        let writes = await config.uiStateUpdateCount - before
        XCTAssertEqual(writes, 0)
    }

    /// `stop()` bekleyen yazımı iptal eder (kapanışta bayat frame yazılmaz).
    func testStopCancelsPendingBoundsPersist() async {
        let config = FakeConfigService()
        let controller = makeController(config)
        _ = install(controller)
        let before = await config.uiStateUpdateCount

        controller.scheduleBoundsPersist()
        controller.stop()
        try? await Task.sleep(for: .milliseconds(120))

        let writes = await config.uiStateUpdateCount - before
        XCTAssertEqual(writes, 0)
    }

    // MARK: - Traffic light + kapanış yönlendirmesi

    func testFocusModeHidesAndRestoresTrafficLights() {
        let controller = makeController(FakeConfigService())
        defer { controller.stop() }
        let window = install(controller)

        controller.setTrafficLightsHidden(true)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, true)

        controller.setTrafficLightsHidden(false)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, false)
        XCTAssertEqual(
            window.standardWindowButton(.closeButton)?.frame.origin.x,
            TrafficLightLayout.leadingInset
        )
    }

    /// Çarpı (X) doğrudan kapatmaz: karar quit akışına yönlendirilir (design/03 §2).
    func testWindowShouldCloseDelegatesToTheQuitFlow() {
        let controller = makeController(FakeConfigService())
        defer { controller.stop() }
        let window = install(controller)
        var asked = 0
        controller.onWindowShouldClose = {
            asked += 1
            return false
        }

        XCTAssertFalse(controller.windowShouldClose(window))
        XCTAssertEqual(asked, 1)
    }
}
