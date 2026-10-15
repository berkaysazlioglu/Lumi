import AppKit
import Foundation
import LumiKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Karar 57 sertleştirmesi: link jestleri artık SENTETİK NSEvent'lerle, gerçek
/// `mouseDown`/`mouseUp` yolundan sürülerek doğrulanır — closure'ları elle
/// çağıran testler "düz tık terminale mi ait" sorusunu kilitleyemiyordu.
@MainActor
final class TerminalLinkViewGestureTests: XCTestCase {
    private static let link = "/tmp/lumi-link-target.txt"

    private var view: DropAwareTerminalView!
    private var activations: [(link: String, gesture: TerminalLinkGesture)] = []

    override func setUp() async throws {
        view = DropAwareTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        view.feed(text: Self.link)
        activations = []
        view.onLinkActivation = { [weak self] link, gesture, _ in
            self?.activations.append((link, gesture))
        }
    }

    override func tearDown() async throws {
        view = nil
    }

    /// Fare raporlayan TUI (Claude `1003`) — düz tık terminale aittir.
    private func enableMouseReporting() {
        view.feed(text: "\u{1B}[?1003h")
        XCTAssertNotEqual(view.getTerminal().mouseMode, .off, "mouse mode kurulamadı")
    }

    /// Linkin ilk karakterinin ortasına denk gelen view noktası.
    private func linkPoint(column: Int = 2) -> NSPoint {
        let cell = view.cellSize
        let x = cell.width * (CGFloat(column) + 0.5)
        let y = view.bounds.height - cell.height * 0.5
        return NSPoint(x: x, y: y)
    }

    private func mouse(
        _ type: NSEvent.EventType,
        at point: NSPoint,
        clickCount: Int = 1,
        flags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: clickCount, pressure: 1
        )!
    }

    private func click(
        at point: NSPoint,
        clickCount: Int = 1,
        flags: NSEvent.ModifierFlags = [],
        dragTo drag: NSPoint? = nil
    ) {
        view.mouseDown(with: mouse(.leftMouseDown, at: point, clickCount: clickCount, flags: flags))
        if let drag {
            view.mouseDragged(with: mouse(.leftMouseDragged, at: drag, clickCount: clickCount, flags: flags))
        }
        view.mouseUp(with: mouse(.leftMouseUp, at: drag ?? point, clickCount: clickCount, flags: flags))
    }

    // MARK: - Düz tık

    func testPlainClickOpensActionsWhenTheTerminalDoesNotReportMouse() {
        click(at: linkPoint())

        XCTAssertEqual(activations.count, 1)
        XCTAssertEqual(activations.first?.link, Self.link)
        XCTAssertEqual(activations.first?.gesture, .actions)
    }

    /// Kullanıcı düzeltmesi: fare raporlayan bir TUI çalışırken
    /// de düz sol tık yeter — ⌘ gerekmez.
    func testPlainClickAlsoWorksWhileMouseReportingIsOn() {
        enableMouseReporting()

        click(at: linkPoint())

        XCTAssertEqual(activations.first?.gesture, .actions)
        XCTAssertEqual(activations.first?.link, Self.link)
    }

    func testPlainClickIsLeftToTheTerminalWhenTheSettingIsOff() {
        view.isLinkActionsEnabled = false

        click(at: linkPoint())

        XCTAssertTrue(activations.isEmpty)
    }

    // MARK: - ⌘ / ⇧⌘

    func testCommandClickWorksEvenWhileMouseReportingIsOn() {
        enableMouseReporting()

        click(at: linkPoint(), flags: [.command])

        XCTAssertEqual(activations.first?.gesture, .primary)
        XCTAssertEqual(activations.first?.link, Self.link)
    }

    func testShiftCommandClickResolvesToTheAlternateGesture() {
        click(at: linkPoint(), flags: [.command, .shift])

        XCTAssertEqual(activations.first?.gesture, .alternate)
    }

    // MARK: - Terminale ait jestler

    /// Çift tık kelime seçimidir: ilk tık popover'ı AÇAR ama ikinci tık
    /// terminale gider (popover dışarı tıkı yutmaz) ve seçim çalışır.
    func testDoubleClickIsLeftToTheTerminal() {
        click(at: linkPoint(), clickCount: 2)

        XCTAssertTrue(activations.isEmpty)
    }

    func testDragCancelsTheGesture() {
        let start = linkPoint()
        click(at: start, dragTo: NSPoint(x: start.x + 120, y: start.y))

        XCTAssertTrue(activations.isEmpty)
    }

    func testShiftClickIsLeftToTheTerminal() {
        click(at: linkPoint(), flags: [.shift])

        XCTAssertTrue(activations.isEmpty)
    }

    func testControlClickIsLeftToTheTerminal() {
        click(at: linkPoint(), flags: [.control])

        XCTAssertTrue(activations.isEmpty)
    }

    /// Linkin olmadığı boş hücrede hiçbir jest doğmaz.
    func testClickOnEmptyCellDoesNothing() {
        let cell = view.cellSize
        click(at: NSPoint(x: cell.width * 60, y: view.bounds.height - cell.height * 10))

        XCTAssertTrue(activations.isEmpty)
    }
}
