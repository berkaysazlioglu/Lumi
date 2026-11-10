import AppKit
import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// Karar 57: düz tıkın fare raporu, tık bir eylem popover'ına dönüşürse PTY'ye
/// hiç gitmez (Claude'un caret'i oynamaz); dönüşmezse olduğu gibi akar.
@MainActor
final class TerminalLinkSessionTests: XCTestCase {
    private func makeSession(pty: FakePTY) throws -> TerminalSession {
        try TerminalSession(
            repoPath: FileManager.default.temporaryDirectory.path,
            name: "link",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            ptySpawner: FakePTYSpawner(pty: pty)
        )
    }

    private func linkView(_ session: TerminalSession) throws -> DropAwareTerminalView {
        try XCTUnwrap(session.terminalView as? DropAwareTerminalView)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    private static let report = Data("\u{1B}[<0;12;4M".utf8)

    func testClaimedGestureDropsDeferredMouseReports() async throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)
        let view = try linkView(session)

        view.onLinkGestureBegan?()
        session.write(Self.report)
        await settle()
        XCTAssertEqual(pty.recorder.totalBytes, 0, "bekletilen rapor PTY'ye sızdı")

        view.onLinkGestureEnded?(true)
        await settle()
        XCTAssertEqual(pty.recorder.totalBytes, 0, "popover açılan tık PTY'ye ulaştı")
    }

    func testUnclaimedGestureFlushesDeferredMouseReports() async throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)
        let view = try linkView(session)

        view.onLinkGestureBegan?()
        session.write(Self.report)
        view.onLinkGestureEnded?(false)
        await settle()

        XCTAssertEqual(pty.recorder.written, Self.report, "iptal edilen jestte rapor akmadı")
    }

    /// Bekletme YALNIZ fare raporlarını tutar — klavye girdisi gecikmez.
    func testKeyboardInputIsNeverDeferred() async throws {
        let pty = FakePTY()
        let session = try makeSession(pty: pty)
        let view = try linkView(session)

        view.onLinkGestureBegan?()
        session.write("ls")
        await settle()

        XCTAssertEqual(pty.recorder.written, Data("ls".utf8))
    }

    func testActivationReachesDelegateWithSessionIdentity() throws {
        let session = try makeSession(pty: FakePTY())
        let delegate = SpyDelegate()
        session.delegate = delegate
        let view = try linkView(session)

        view.onLinkActivation?(TerminalClickedLink(text: "/tmp/a.swift"), .primary, CGPoint(x: 10, y: 20))

        XCTAssertEqual(delegate.linkActivations.count, 1)
        XCTAssertEqual(delegate.linkActivations.first?.terminalID, session.id)
        XCTAssertEqual(delegate.linkActivations.first?.link, "/tmp/a.swift")
        XCTAssertEqual(delegate.linkActivations.first?.gesture, .primary)
        XCTAssertEqual(delegate.linkActivations.first?.anchor, CGPoint(x: 10, y: 20))
        XCTAssertEqual(delegate.linkActivations.first?.source, .text)
    }

    /// Karar 149: görsel tıkı türünü delegate'e taşır.
    func testImageActivationCarriesItsSource() throws {
        let session = try makeSession(pty: FakePTY())
        let delegate = SpyDelegate()
        session.delegate = delegate
        let view = try linkView(session)

        view.onLinkActivation?(TerminalClickedLink(text: "/tmp/i/1.png", source: .image), .actions, .zero)

        XCTAssertEqual(delegate.linkActivations.first?.link, "/tmp/i/1.png")
        XCTAssertEqual(delegate.linkActivations.first?.source, .image)
    }
}
