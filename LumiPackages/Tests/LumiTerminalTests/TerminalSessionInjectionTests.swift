import AppKit
import Foundation
import LumiKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Faz 4.1: `TerminalSession` artık PTY'yi ve view'ı kendi `new`'lemediği için
/// gerçek fork/exec olmadan birim test edilebilir. Emülatör gerçek (headless
/// SwiftTerm view), PTY sahte.
@MainActor
final class TerminalSessionInjectionTests: XCTestCase {
    private func makeSession(
        pty: FakePTY,
        viewMaker: any TerminalViewMaking = DropAwareTerminalViewMaker()
    ) throws -> TerminalSession {
        try TerminalSession(
            repoPath: FileManager.default.temporaryDirectory.path,
            name: "injected",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            ptySpawner: FakePTYSpawner(pty: pty),
            viewMaker: viewMaker
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - PTY enjeksiyonu

    func testWritesReachInjectedPTYThroughInputFilter() async throws {
        // Arrange
        let pty = FakePTY()
        let session = try makeSession(pty: pty)

        // Act — focus event'i (ESC[I) koşulsuz ayıklanır, gerisi geçer
        session.write("\u{1B}[Ihello")

        // Assert
        let arrived = await waitUntil { pty.recorder.totalBytes > 0 }
        XCTAssertTrue(arrived, "yazım enjekte edilen PTY'ye ulaşmadı")
        XCTAssertEqual(pty.recorder.written, Data("hello".utf8))
    }

    func testTerminateForwardsToInjectedPTY() throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)

        session.terminate()

        XCTAssertEqual(pty.terminations, 1)
    }

    func testRequestRepaintPokesPTYAndRedrawDoesNot() throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)

        // Poke'suz tam çizim (presentation'ın kendi yüzü) SIGWINCH üretmez.
        session.presentation.redrawFromBuffer()
        XCTAssertEqual(pty.pokes, 0, "poke'suz çizim SIGWINCH göndermemeli")

        session.requestRepaint()
        XCTAssertEqual(pty.pokes, 1)
    }

    /// PTY exit'i delegate'e ulaşır ve sonrasında oturum susar (bayat sinyal yok).
    func testExitNotifiesDelegateAndSilencesLaterSignals() async throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)
        let delegate = SpyDelegate()
        session.delegate = delegate

        pty.onExit?(3)
        let exited = await waitUntil { delegate.exitCodes == [3] }
        XCTAssertTrue(exited, "exit delegate'e ulaşmadı: \(delegate.exitCodes)")

        session.bell(source: session.terminalView)
        XCTAssertEqual(delegate.bells, 0, "exit sonrası bell yayıldı")
    }

    // MARK: - View fabrikası + katman sınırı

    func testViewMakerProducesTheSessionView() throws {
        let maker = SpyViewMaker()
        let session = try makeSession(pty: FakePTY(), viewMaker: maker)

        XCTAssertTrue(session.terminalView === maker.made, "oturum fabrikanın view'ını kullanmadı")
        XCTAssertEqual(
            session.terminalView.getTerminal().options.scrollback,
            TerminalSession.scrollbackLines,
            "scrollback paritesi (5000) uygulanmadı"
        )
    }

    /// Katman ihlali düzeltmesi: font değişimi `superview.needsLayout` yerine
    /// enjekte edilebilir bir callback'le bildirilir.
    func testSetFontInvalidatesLayoutThroughCallback() throws {
        let session = try makeSession(pty: FakePTY())
        var invalidations = 0
        session.onLayoutInvalidated = { invalidations += 1 }

        session.setFont(.monospacedSystemFont(ofSize: 16, weight: .regular))

        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(session.terminalView.font.pointSize, 16)
    }

    func testTerminatedSessionIgnoresVisualCommands() async throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)
        pty.onExit?(0)
        _ = await waitUntil { session.isTerminated }

        var invalidations = 0
        session.onLayoutInvalidated = { invalidations += 1 }
        session.setFont(.monospacedSystemFont(ofSize: 20, weight: .regular))
        session.requestRepaint()

        XCTAssertEqual(invalidations, 0)
        XCTAssertEqual(pty.pokes, 0)
    }
}

@MainActor
private final class SpyViewMaker: TerminalViewMaking {
    private(set) var made: TerminalView?

    func makeView(frame: NSRect, font: NSFont) -> TerminalView {
        let view = DropAwareTerminalView(frame: frame, font: font)
        made = view
        return view
    }
}

@MainActor
private final class SpyDelegate: TerminalSessionDelegate {
    private(set) var exitCodes: [Int32] = []
    private(set) var bells = 0
    private(set) var stalls: [Bool] = []

    func session(_ session: TerminalSession, didChangeStatus status: TerminalStatus) {}
    func session(_ session: TerminalSession, didChangeAwaitingDecision awaiting: Bool) {}
    func session(_ session: TerminalSession, didChangeTitle title: String) {}
    func session(_ session: TerminalSession, didChangeStalled stalled: Bool) {
        stalls.append(stalled)
    }

    func session(_ session: TerminalSession, didExitWithCode code: Int32) {
        exitCodes.append(code)
    }

    func session(_ session: TerminalSession, didFailWriteWithErrno code: Int32) {}

    func sessionDidBell(_ session: TerminalSession) {
        bells += 1
    }
}
