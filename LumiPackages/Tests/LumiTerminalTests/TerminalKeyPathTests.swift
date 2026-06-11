import AppKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Backspace teşhisi: SwiftTerm tuş katmanını izole eder.
/// keyDown → interpretKeyEvents → doCommand(deleteBackward) → delegate.send(0x7f)
/// zincirinin hangi halkada koptuğunu saptamak için katman katman test.
@MainActor
final class TerminalKeyPathTests: XCTestCase {
    private final class SendCapturingDelegate: TerminalViewDelegate {
        var captured: [[UInt8]] = []
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            captured.append(Array(data))
        }
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private struct Fixture {
        let window: NSWindow
        let view: TerminalView
        let capture: SendCapturingDelegate
    }

    private func makeFixture() -> Fixture {
        let capture = SendCapturingDelegate()
        let view = TerminalView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        view.terminalDelegate = capture
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(view)
        window.makeFirstResponder(view)
        return Fixture(window: window, view: view, capture: capture)
    }

    private func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testDoCommandDeleteBackwardSendsDEL() {
        let fixture = makeFixture()
        fixture.view.doCommand(by: #selector(NSStandardKeyBindingResponding.deleteBackward(_:)))
        XCTAssertEqual(fixture.capture.captured, [[0x7F]], "doCommand katmanı 0x7f üretmedi")
    }

    func testKeyDownDeleteSendsDEL() {
        let fixture = makeFixture()
        fixture.view.keyDown(with: keyEvent("\u{7f}", keyCode: 51, window: fixture.window))
        XCTAssertEqual(
            fixture.capture.captured, [[0x7F]],
            "keyDown→interpretKeyEvents katmanı 0x7f üretmedi: \(fixture.capture.captured)"
        )
    }

    func testPrintableKeyDownSendsCharacter() {
        let fixture = makeFixture()
        fixture.view.keyDown(with: keyEvent("a", keyCode: 0, window: fixture.window))
        XCTAssertEqual(
            fixture.capture.captured, [Array("a".utf8)],
            "düz karakter yolu: \(fixture.capture.captured)"
        )
    }

    /// Kitty keyboard protokolü yolu (claude CLI bunu açar): backspace'in
    /// kitty-encoded biçimi de delegate'e ulaşmalı (boş olmamalı).
    func testKittyModeBackspaceStillSendsSomething() {
        let fixture = makeFixture()
        // CSI > 1 u — keyboardEnhancementFlags'i set eder (disambiguate escapes)
        fixture.view.getTerminal().feed(text: "\u{1B}[>1u")
        fixture.view.keyDown(with: keyEvent("\u{7f}", keyCode: 51, window: fixture.window))
        XCTAssertFalse(
            fixture.capture.captured.isEmpty,
            "kitty modunda backspace hiçbir byte üretmedi"
        )
    }
}
