import AppKit
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiUI

/// Refactor 4.5: terminal view'ının frame'ini oturtan TEK yer host container'dır
/// (`TerminalGridFit.fit`). Registry yalnız reparent eder; host her AppKit layout
/// geçişinde (setFrameSize/layout) kendini onarır.
@MainActor
final class TerminalHostContainerTests: XCTestCase {
    private func makeHost(
        id: TerminalID,
        provider: FakeTerminalViewProvider
    ) -> (TerminalHostContainer, NSView) {
        let host = TerminalHostContainer(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.terminalID = id
        host.provider = provider
        let terminalView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        host.addSubview(terminalView)
        return (host, terminalView)
    }

    /// Hücre geometrisi bildirmeyen view (test double) tam bounds'a oturur.
    func testHostFitsTerminalViewOnEveryFrameChange() {
        let provider = FakeTerminalViewProvider()
        let (host, terminalView) = makeHost(id: TerminalID(), provider: provider)

        host.setFrameSize(NSSize(width: 500, height: 320))
        XCTAssertEqual(terminalView.frame, NSRect(x: 0, y: 0, width: 500, height: 320))

        host.setFrameSize(NSSize(width: 260, height: 180))
        XCTAssertEqual(terminalView.frame, NSRect(x: 0, y: 0, width: 260, height: 180))

        host.layout()
        XCTAssertEqual(terminalView.frame, NSRect(x: 0, y: 0, width: 260, height: 180))
    }

    /// Layout öncesi 0×0'a pinlenmez (SwiftTerm'i sıfıra küçültmek emülatörü
    /// gereksiz resize eder) — bilinçli davranış, 4.5'te korunur.
    func testZeroSizedHostDoesNotFitTerminalView() {
        let provider = FakeTerminalViewProvider()
        let (host, terminalView) = makeHost(id: TerminalID(), provider: provider)

        host.setFrameSize(.zero)

        XCTAssertEqual(terminalView.frame.size, NSSize(width: 800, height: 480))
    }

    /// Reassert reparenting yarışına karşı korunur: her layout geçişi terminalini
    /// yeniden claim eder (registry tarafında zaten bağlıysa no-op).
    func testEveryLayoutPassReassertsAttachment() {
        let id = TerminalID()
        let provider = FakeTerminalViewProvider()
        let (host, _) = makeHost(id: id, provider: provider)

        host.setFrameSize(NSSize(width: 500, height: 320))
        host.layout()

        XCTAssertEqual(provider.attachCalls.map(\.id), [id, id])
        XCTAssertEqual(provider.detachCalls.count, 0)
    }
}
