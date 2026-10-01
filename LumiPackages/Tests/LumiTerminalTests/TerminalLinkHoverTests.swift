import AppKit
import Foundation
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Link hover'ı (Orca paritesi): düz hover linkin altını çizer ve imleci ele
/// çevirir; Claude'un anyEvent fare modunda da hover yeniden oynatılır ama
/// SwiftTerm'in buglu hover raporu PTY'ye hiç gitmez.
@MainActor
final class TerminalLinkHoverTests: XCTestCase {
    private static let link = "/tmp/lumi-link-target.txt"

    private final class SpyDelegate: TerminalViewDelegate {
        var sent: [[UInt8]] = []
        var openedLinks: [String] = []
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(Array(data)) }
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            openedLinks.append(link)
        }
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private var view: DropAwareTerminalView!
    private var spy: SpyDelegate!
    private var activations = 0

    override func setUp() async throws {
        view = DropAwareTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        spy = SpyDelegate()
        view.terminalDelegate = spy
        view.feed(text: Self.link)
        activations = 0
        view.onLinkActivation = { [weak self] _, _, _ in self?.activations += 1 }
    }

    override func tearDown() async throws {
        view = nil
        spy = nil
    }

    private func linkPoint() -> NSPoint {
        let cell = view.cellSize
        return NSPoint(x: cell.width * 2.5, y: view.bounds.height - cell.height * 0.5)
    }

    private func emptyPoint() -> NSPoint {
        let cell = view.cellSize
        return NSPoint(x: cell.width * 60, y: view.bounds.height - cell.height * 10)
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    @discardableResult
    private func hover(at point: NSPoint, flags: NSEvent.ModifierFlags = []) -> Bool {
        view.handleHover(locationInWindow: point, event: mouse(.mouseMoved, at: point, flags: flags))
    }

    // MARK: - Vurgu modu

    func testPlainHoverHighlightsWhileLinkActionsAreEnabled() {
        XCTAssertEqual(view.linkHighlightMode, .hover)

        view.isLinkActionsEnabled = false
        XCTAssertEqual(view.linkHighlightMode, .hoverWithModifier, "kapalıyken vurgu ⌘ istemeli")

        view.isLinkActionsEnabled = true
        XCTAssertEqual(view.linkHighlightMode, .hover)
    }

    // MARK: - İmleç

    func testCursorTurnsIntoHandOnlyOverALink() {
        hover(at: linkPoint())
        XCTAssertTrue(view.isPointingAtLink)

        hover(at: emptyPoint())
        XCTAssertFalse(view.isPointingAtLink)
    }

    func testCursorNeedsCommandWhenLinkActionsAreDisabled() {
        view.isLinkActionsEnabled = false

        hover(at: linkPoint())
        XCTAssertFalse(view.isPointingAtLink, "düz tık bir şey yapmıyorsa el imleci yanıltır")

        hover(at: linkPoint(), flags: [.command])
        XCTAssertTrue(view.isPointingAtLink)
    }

    func testLeavingTheTerminalReleasesTheHandCursor() {
        hover(at: linkPoint())
        view.clearLinkHover()

        XCTAssertFalse(view.isPointingAtLink)
    }

    // MARK: - anyEvent (Claude 1003) modu

    func testHoverInAnyEventModeIsReplayedWithoutReachingThePTY() {
        view.feed(text: "\u{1B}[?1003h\u{1B}[?1006h")
        XCTAssertEqual(view.getTerminal().mouseMode, .anyEvent)

        XCTAssertTrue(hover(at: linkPoint()), "event AppKit'e bırakılırsa buglu rapor PTY'ye gider")
        XCTAssertTrue(spy.sent.isEmpty, "hover raporu düşürülmedi: \(spy.sent)")
        XCTAssertTrue(view.isPointingAtLink)
    }

    func testHoverOutsideAnyEventModeIsLeftToSwiftTerm() {
        XCTAssertFalse(hover(at: linkPoint()))
        XCTAssertTrue(view.isPointingAtLink)
    }

    // MARK: - Tık

    /// `.hover` modunda SwiftTerm vurgulu linke düz tıkta linki kendisi açardı;
    /// link tıkının sahibi Lumi'nin popover yoludur.
    func testPlainClickOnHighlightedLinkDoesNotOpenItThroughSwiftTerm() {
        view.mouseMoved(with: mouse(.mouseMoved, at: linkPoint()))

        view.mouseDown(with: mouse(.leftMouseDown, at: linkPoint()))
        view.mouseUp(with: mouse(.leftMouseUp, at: linkPoint()))

        XCTAssertTrue(spy.openedLinks.isEmpty, "SwiftTerm linki popover'ın yanında ayrıca açtı")
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(view.linkHighlightMode, .hover, "tık sonrası vurgu modu geri dönmeli")
    }
}
