import AppKit
import LumiKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// `TerminalEventMonitor` (refactor 4.7 + 4.6): terminal başına monitör yerine tek
/// uygulama-seviyesi monitör; hedef terminal hit-test ile bulunur ve üstteki overlay
/// olayı doğal yoluna bırakır (eski `TerminalInputGate.shared` bayrağının yerine).
@MainActor
final class TerminalEventMonitorTests: XCTestCase {
    private static let windowFrame = NSRect(x: 0, y: 0, width: 800, height: 400)

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: Self.windowFrame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: Self.windowFrame)
        return window
    }

    private func makeTerminalView(frame: NSRect) -> DropAwareTerminalView {
        DropAwareTerminalView(frame: frame, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    /// Sol/sağ yan yana iki terminal (grid paritesi).
    private func makeTwoTerminalWindow() -> (NSWindow, DropAwareTerminalView, DropAwareTerminalView) {
        let window = makeWindow()
        let left = makeTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let right = makeTerminalView(frame: NSRect(x: 400, y: 0, width: 400, height: 400))
        window.contentView?.addSubview(left)
        window.contentView?.addSubview(right)
        return (window, left, right)
    }

    // MARK: - Yaşam döngüsü

    func testStartAndStopAreIdempotent() {
        let monitor = TerminalEventMonitor()
        XCTAssertFalse(monitor.isRunning)

        monitor.start { _ in }
        XCTAssertTrue(monitor.isRunning)
        monitor.start { _ in } // ikinci kayıt olmamalı
        XCTAssertTrue(monitor.isRunning)

        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        monitor.stop() // idempotent
        XCTAssertFalse(monitor.isRunning)
    }

    // MARK: - Hit-test yönlendirmesi (N terminal → 1 monitör)

    func testPointerRoutesToTerminalUnderCursor() {
        let (window, left, right) = makeTwoTerminalWindow()

        XCTAssertTrue(
            TerminalEventMonitor.terminalView(at: NSPoint(x: 100, y: 200), in: window) === left
        )
        XCTAssertTrue(
            TerminalEventMonitor.terminalView(at: NSPoint(x: 600, y: 200), in: window) === right
        )
    }

    func testPointerOutsideAnyTerminalResolvesToNil() {
        let window = makeWindow()
        let view = makeTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView?.addSubview(view)

        XCTAssertNil(TerminalEventMonitor.terminalView(at: NSPoint(x: 700, y: 350), in: window))
    }

    /// Refactor 4.6: terminalin üstündeki overlay hit-test'i kazanır → terminal
    /// bulunamaz, event yutulmaz ve AppKit'in normal dağıtımı overlay'e gider.
    func testOverlayAboveTerminalTakesTheHit() {
        let (window, left, _) = makeTwoTerminalWindow()
        let overlay = NSView(frame: Self.windowFrame) // tam-ekran Settings/FileViewer analogu
        window.contentView?.addSubview(overlay)

        XCTAssertNil(
            TerminalEventMonitor.terminalView(at: NSPoint(x: 100, y: 200), in: window),
            "overlay üstteyken event terminale yönlendirildi"
        )
        XCTAssertTrue(left.superview != nil, "terminal hierarchy'de kalmalı — yalnız hit-test değişir")

        overlay.removeFromSuperview()
        XCTAssertTrue(TerminalEventMonitor.terminalView(at: NSPoint(x: 100, y: 200), in: window) === left)
    }

    // MARK: - Scroll kararı (overlay varken yutulmaz, yokken yutulur)

    func testScrollIsConsumedOnlyWhenNoOverlayCoversTheTerminal() {
        // Arrange — alt-buffer (TUI) modundaki terminal: wheel köprüsü aktif
        let monitor = TerminalEventMonitor()
        let (window, left, _) = makeTwoTerminalWindow()
        left.getTerminal().feed(text: "\u{1B}[?1049h")
        XCTAssertTrue(left.getTerminal().isCurrentBufferAlternate)
        let cursor = NSPoint(x: 100, y: 200)

        // Act + Assert — overlay yokken terminal wheel'i üstlenir
        XCTAssertTrue(
            monitor.routePointer(isScroll: true, locationInWindow: cursor, in: window, deltaY: 30)
        )

        // Act + Assert — overlay açıkken event doğal yoluna bırakılır
        let overlay = NSView(frame: Self.windowFrame)
        window.contentView?.addSubview(overlay)
        XCTAssertFalse(
            monitor.routePointer(isScroll: true, locationInWindow: cursor, in: window, deltaY: 30),
            "overlay açıkken scroll hâlâ terminale gitti"
        )
    }

    /// Hover yalnız anyEvent (1003) modunda yutulur — SwiftTerm'in hover'ı "sol buton
    /// release" olarak kodlayan upstream bug'ı. Diğer modlarda davranış değişmez.
    func testHoverIsConsumedOnlyInAnyEventMouseMode() {
        let monitor = TerminalEventMonitor()
        let (window, left, _) = makeTwoTerminalWindow()
        let cursor = NSPoint(x: 100, y: 200)

        XCTAssertFalse(monitor.routePointer(isScroll: false, locationInWindow: cursor, in: window))

        left.getTerminal().feed(text: "\u{1B}[?1003h")
        XCTAssertEqual(left.getTerminal().mouseMode, .anyEvent)
        XCTAssertTrue(monitor.routePointer(isScroll: false, locationInWindow: cursor, in: window))
    }

    // MARK: - Klavye eşlemesi (manager'dan taşındı, davranış birebir)

    func testKeyDownMappingReachesFirstResponderTerminal() {
        // Arrange
        let monitor = TerminalEventMonitor()
        let (window, left, _) = makeTwoTerminalWindow()
        let capture = SendCapturingDelegate()
        left.terminalDelegate = capture
        window.makeFirstResponder(left)

        // Act — Option+Backspace → ^W (NaturalEditingKeyMap)
        let mapped = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: 51
        )!

        // Assert
        XCTAssertTrue(monitor.routeKeyDown(mapped), "eşlenen tuş yutulmadı")
        XCTAssertEqual(capture.captured, [[0x17]])
    }

    func testUnmappedKeyDownIsLeftToSwiftTerm() {
        let monitor = TerminalEventMonitor()
        let (window, left, _) = makeTwoTerminalWindow()
        window.makeFirstResponder(left)

        let plain = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0
        )!

        XCTAssertFalse(monitor.routeKeyDown(plain))
    }
}

/// SwiftTerm delegate'ine giden byte'ları yakalar.
private final class SendCapturingDelegate: TerminalViewDelegate {
    var captured: [[UInt8]] = []
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { captured.append(Array(data)) }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
