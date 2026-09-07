import AppKit
import LumiKit
import XCTest
@testable import LumiTerminal

/// `setFocused(id)` (store'un odak otoritesi) AppKit first responder'ı da
/// taşımalı — Electron `setActiveTerminal` → `terminal.focus()` paritesi.
@MainActor
final class TerminalSessionManagerKeyboardFocusTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        return window
    }

    func testSetFocusedMakesAttachedTerminalViewFirstResponder() throws {
        // Arrange — iki kart, ikisi de pencerede; ilki fareyle odaklanmış gibi FR
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }
        let tmp = FileManager.default.temporaryDirectory.path
        let first = try manager.spawn(repoPath: tmp, task: nil, command: nil)
        let second = try manager.spawn(repoPath: tmp, task: nil, command: nil)
        let window = makeWindow()
        for id in [first.id, second.id] {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 150))
            window.contentView?.addSubview(container)
            manager.viewRegistry.attachView(for: id, into: container)
        }
        let firstView = try XCTUnwrap(manager.sessions[0].terminalView)
        let secondView = try XCTUnwrap(manager.sessions[1].terminalView)
        window.makeFirstResponder(firstView)
        XCTAssertTrue(window.firstResponder === firstView)

        // Act — Cmd+2 / focusNext
        manager.setFocused(second.id)

        // Assert
        XCTAssertTrue(window.firstResponder === secondView, "setFocused klavye odağını taşımadı")
    }

    func testSetFocusedBeforeAttachIsFulfilledWhenViewAttaches() throws {
        // Cmd+T: spawn → store focus(id) → setFocused; view daha sonra bağlanır.
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }
        let meta = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path, task: nil, command: nil
        )
        let view = try XCTUnwrap(manager.sessions.last?.terminalView)
        let window = makeWindow()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 150))
        window.contentView?.addSubview(container)

        // Act
        manager.setFocused(meta.id)
        manager.viewRegistry.attachView(for: meta.id, into: container)

        // Assert
        XCTAssertTrue(window.firstResponder === view)
    }
}
