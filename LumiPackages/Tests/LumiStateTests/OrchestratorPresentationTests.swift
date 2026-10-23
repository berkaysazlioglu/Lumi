import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 124: orchestrator'ın docked paneli ile popup'ı arasındaki geçişler.
@MainActor
final class OrchestratorPresentationTests: XCTestCase {
    private var layout: LayoutStore!
    private var dialogs: DialogRouter!
    private var presentation: OrchestratorPresentation!

    override func setUp() async throws {
        let config = FakeConfigService()
        layout = LayoutStore(config: config) { _, _ in false }
        dialogs = DialogRouter()
        let store = OrchestratorStore(
            terminal: FakeTerminalService(),
            viewProvider: FakeTerminalViewProvider(),
            launcher: FakeOrchestratorLauncher(),
            config: config,
            workingDirectory: "/home/.lumi/orchestrator"
        )
        presentation = OrchestratorPresentation(layout: layout, dialogs: dialogs, orchestrator: store)
    }

    func testToggleOpensAndClosesThePanel() {
        XCTAssertEqual(presentation.panelSlot, .innerRight)
        presentation.toggle()
        XCTAssertTrue(layout.isSlotVisible(.innerRight))
        XCTAssertFalse(dialogs.isOrchestratorOpen)
        presentation.toggle()
        XCTAssertFalse(layout.isSlotVisible(.innerRight))
    }

    func testToggleClosesPopupFirstAndKeepsThePanel() {
        presentation.showPanel()
        presentation.openPopup()
        XCTAssertTrue(presentation.isPresented)

        presentation.toggle()

        XCTAssertFalse(dialogs.isOrchestratorOpen)
        XCTAssertTrue(layout.isSlotVisible(.innerRight), "popup'tan panele dönülür")
    }

    func testToggleOpensPopupInFocusMode() {
        layout.toggleFocusMode()
        presentation.toggle()
        XCTAssertTrue(dialogs.isOrchestratorOpen, "focus mode'da paneller çizilmez")
        XCTAssertFalse(layout.visibleSlots.contains(.innerRight))
    }

    func testDockClosesPopupAndShowsPanel() {
        presentation.openPopup()
        presentation.dock()
        XCTAssertFalse(dialogs.isOrchestratorOpen)
        XCTAssertTrue(layout.isSlotVisible(.innerRight))
    }

    func testShowingPanelClosesRightSidebarByDefault() {
        layout.setSlotVisible(.right, true)
        presentation.showPanel()
        XCTAssertFalse(layout.isSlotVisible(.right))

        layout.setExclusiveRightPanels(false)
        layout.setSlotVisible(.right, true)
        XCTAssertTrue(layout.isSlotVisible(.right))
        XCTAssertTrue(layout.isSlotVisible(.innerRight), "kural kapalıyken ikisi birlikte açık")
    }
}
