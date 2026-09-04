import AppKit
import LumiKit
import XCTest
@testable import LumiTerminal

/// Faz 3.7: terminal NSView odağı artık `onTerminalViewFocused` callback'iyle
/// değil, `TerminalEvent.viewFocused` ile yayınlanır — store köprüsü composition
/// root'tan event akışına iner.
@MainActor
final class TerminalSessionManagerViewFocusTests: XCTestCase {
    func testViewFocusIsBroadcastAsEvent() async throws {
        // Arrange
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }
        var iterator = manager.events().makeAsyncIterator()
        let meta = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path,
            task: nil,
            command: nil
        )
        let session = try XCTUnwrap(manager.sessions.last)

        // Act
        manager.noteViewFocused(session.terminalView)

        // Assert — spawn/status event'leri arasından odak event'i çıkar
        // (noteViewFocused senkron yayınladığı için akış asla beklemede kalmaz).
        var seen: [TerminalEvent] = []
        while let event = await iterator.next() {
            seen.append(event)
            if event == .viewFocused(meta.id) { return }
            if seen.count > 32 { break }
        }
        XCTFail(".viewFocused yayınlanmadı; görülenler: \(seen)")
    }

    func testUnknownViewProducesNoEvent() throws {
        let manager = TerminalSessionManager()
        defer { manager.shutdown() }

        // Kayıtlı olmayan view → sessiz (bayat first-responder koruması)
        manager.noteViewFocused(NSView())
    }
}
