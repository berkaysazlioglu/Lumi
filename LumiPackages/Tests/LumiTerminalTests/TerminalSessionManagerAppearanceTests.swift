import AppKit
import LumiKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Faz 3.7: `TerminalAppearanceControlling` — font/cursor artık setter değil,
/// protokol metodu. Canlı oturumlara uygulanır ve sonraki spawn'lar devralır.
@MainActor
final class TerminalSessionManagerAppearanceTests: XCTestCase {
    private func spawnSession(_ manager: TerminalSessionManager) throws -> TerminalSession {
        _ = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path,
            task: nil,
            command: nil
        )
        return try XCTUnwrap(manager.sessions.last)
    }

    func testApplyFontUpdatesLiveSessions() throws {
        // Arrange
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }
        let session = try spawnSession(manager)
        let target = NSFont.monospacedSystemFont(ofSize: 19, weight: .regular)

        // Act
        manager.applyFont(target)

        // Assert
        XCTAssertEqual(session.terminalView.font, target)
    }

    func testApplyFontIsInheritedByLaterSpawns() throws {
        // Arrange
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }
        let target = NSFont.monospacedSystemFont(ofSize: 21, weight: .regular)

        // Act
        manager.applyFont(target)
        let session = try spawnSession(manager)

        // Assert
        XCTAssertEqual(session.terminalView.font, target)
    }

    func testApplyCursorUpdatesLiveSessions() throws {
        // Arrange
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }
        let session = try spawnSession(manager)

        // Act
        manager.applyCursor(shape: .bar, blink: false)

        // Assert
        XCTAssertEqual(session.terminalView.getTerminal().options.cursorStyle, .steadyBar)
    }

    func testApplyCursorIsInheritedByLaterSpawns() throws {
        // Arrange
        let manager = TerminalSessionManager()
        defer { manager.killAll(); manager.shutdown() }

        // Act
        manager.applyCursor(shape: .underline, blink: false)
        let session = try spawnSession(manager)

        // Assert
        XCTAssertEqual(
            session.terminalView.getTerminal().options.cursorStyle,
            .steadyUnderline
        )
    }

    /// Protokol bölünmesi gerçekten iki yüzü de karşılıyor mu (existential kontrol).
    func testManagerSatisfiesBothProtocolFaces() {
        let manager = TerminalSessionManager()
        defer { manager.shutdown() }

        XCTAssertTrue(manager as Any is any TerminalSessionControlling)
        XCTAssertTrue(manager as Any is any TerminalAppearanceControlling)
        XCTAssertTrue(manager as Any is any TerminalServicing)
    }
}
