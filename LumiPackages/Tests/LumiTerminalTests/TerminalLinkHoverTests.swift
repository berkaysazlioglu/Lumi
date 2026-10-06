import AppKit
import Foundation
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Link hover'ı (karar 101 + 116): altı çizgi Lumi'nindir — yalnız diskte VAR
/// olan yolun (ve URL'nin) altı çizilir, imleç ele döner; Claude'un anyEvent
/// fare modunda SwiftTerm'in buglu hover raporu PTY'ye hiç gitmez.
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

    /// Diskte var sayılan yollar (satır içi sorgu — testler beklemez).
    private final class FakeDisk: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: Set<String>
        private(set) var probes: [String] = []

        init(_ paths: Set<String>) { self.paths = paths }

        func exists(_ path: String) -> Bool {
            lock.withLock {
                probes.append(path)
                return paths.contains(path)
            }
        }
    }

    private var view: DropAwareTerminalView!
    private var spy: SpyDelegate!
    private var disk: FakeDisk!
    private var activations: [String] = []

    override func setUp() async throws {
        view = DropAwareTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        spy = SpyDelegate()
        view.terminalDelegate = spy
        useDisk([Self.link])
        view.linkBaseDirectory = "/repo"
        view.feed(text: Self.link)
        activations = []
        view.onLinkActivation = { [weak self] link, _, _ in self?.activations.append(link) }
    }

    override func tearDown() async throws {
        view = nil
        spy = nil
        disk = nil
    }

    private func useDisk(_ paths: Set<String>) {
        let disk = FakeDisk(paths)
        self.disk = disk
        view.linkPathCache = TerminalLinkPathCache(probe: { disk.exists($0) }, runsInline: true)
    }

    private func point(column: Int, row: Int = 0) -> NSPoint {
        let cell = view.cellSize
        return NSPoint(x: cell.width * (CGFloat(column) + 0.5), y: view.bounds.height - cell.height * (CGFloat(row) + 0.5))
    }

    private func linkPoint() -> NSPoint { point(column: 2) }
    private func emptyPoint() -> NSPoint { point(column: 60, row: 10) }

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

    private func show(_ text: String) {
        view.feed(text: "\u{1B}[2J\u{1B}[H" + text)
        view.clearLinkHover()
    }

    // MARK: - Vurgu

    /// SwiftTerm'in kendi hover vurgusu kapalıdır; çizgi Lumi katmanındadır.
    func testSwiftTermHoverHighlightIsOffAndLumiDrawsTheUnderline() {
        XCTAssertEqual(view.linkHighlightMode, .alwaysWithModifier)

        hover(at: linkPoint())

        XCTAssertEqual(view.underlinedLinkText, Self.link)
        XCTAssertEqual(view.linkUnderline.spans, [TerminalLinkSpan(row: 0, columns: 0 ..< 25)])
    }

    func testMissingPathIsNotUnderlined() {
        useDisk([])

        hover(at: linkPoint())

        XCTAssertNil(view.underlinedLinkText)
        XCTAssertFalse(view.isPointingAtLink)
        XCTAssertEqual(disk.probes, [Self.link])
    }

    func testURLIsUnderlinedWithoutAskingTheDisk() {
        useDisk([])
        show("open https://lumi.dev/docs now")

        hover(at: point(column: 8))

        XCTAssertEqual(view.underlinedLinkText, "https://lumi.dev/docs")
        XCTAssertTrue(disk.probes.isEmpty)
    }

    /// Çıplak dosya adı terminalin dizinine göre diske sorulur.
    func testBareFilenameIsALinkOnlyWhenItExists() {
        useDisk(["/repo/README.md"])
        show("README.md  missing.txt")

        hover(at: point(column: 1))
        XCTAssertEqual(view.underlinedLinkText, "README.md")

        hover(at: point(column: 13))
        XCTAssertNil(view.underlinedLinkText)
    }

    func testRoutePathWithParensAndBracketsIsOneLink() {
        let path = "/repo/app/(shop)/[id]/page.tsx"
        useDisk([path])
        show("Error in app/(shop)/[id]/page.tsx:4:2")

        hover(at: point(column: 14))

        XCTAssertEqual(view.underlinedLinkText, "app/(shop)/[id]/page.tsx:4:2")
    }

    /// Boşluklu aday diskte yoksa düz yol yine link olur.
    func testShorterCandidateWinsWhenLongerOneIsMissing() {
        useDisk(["/repo/src/foo"])
        show("src/foo is great")

        hover(at: point(column: 2))

        XCTAssertEqual(view.underlinedLinkText, "src/foo")
    }

    /// Satırı dolduran yol bir alt satıra sarılır; iki parça da çizilir.
    func testWrappedPathIsJoinedAcrossRows() {
        let cols = view.getTerminal().cols
        let path = "/tmp/" + String(repeating: "a", count: cols - 5) + "/tail.txt"
        useDisk([path])
        show(path)

        hover(at: point(column: 3, row: 1))

        XCTAssertEqual(view.underlinedLinkText, path)
        XCTAssertEqual(view.linkUnderline.spans.map(\.row), [0, 1])
    }

    // MARK: - İmleç

    func testCursorTurnsIntoHandOnlyOverALink() {
        hover(at: linkPoint())
        XCTAssertTrue(view.isPointingAtLink)

        hover(at: emptyPoint())
        XCTAssertFalse(view.isPointingAtLink)
        XCTAssertNil(view.underlinedLinkText)
    }

    func testUnderlineAndCursorNeedCommandWhenLinkActionsAreDisabled() {
        view.isLinkActionsEnabled = false

        hover(at: linkPoint())
        XCTAssertFalse(view.isPointingAtLink, "düz tık bir şey yapmıyorsa el imleci yanıltır")
        XCTAssertNil(view.underlinedLinkText)

        view.noteModifierFlags([.command])
        XCTAssertTrue(view.isPointingAtLink, "⌘'ye basmak fareyi oynatmadan vurgulamalı")
        XCTAssertEqual(view.underlinedLinkText, Self.link)

        view.noteModifierFlags([])
        XCTAssertFalse(view.isPointingAtLink)
    }

    func testLeavingTheTerminalReleasesTheHandCursor() {
        hover(at: linkPoint())
        view.clearLinkHover()

        XCTAssertFalse(view.isPointingAtLink)
        XCTAssertNil(view.underlinedLinkText)
    }

    /// Çıktı vurgulanan link'in yerini değiştirdiyse çizgi bayat kalmaz.
    func testContentChangeDropsAStaleUnderline() {
        hover(at: linkPoint())
        view.feed(text: "\u{1B}[2J\u{1B}[H")

        view.noteLinkContentChanged()

        XCTAssertNil(view.underlinedLinkText)
    }

    func testScrollDropsTheUnderline() {
        hover(at: linkPoint())

        _ = view.consumeScroll(deltaY: 1, isPrecise: false, locationInWindow: linkPoint())

        XCTAssertNil(view.underlinedLinkText)
    }

    // MARK: - anyEvent (Claude 1003) modu

    func testHoverInAnyEventModeIsConsumedWithoutReachingThePTY() {
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

    /// Link tıkının sahibi Lumi'nin popover yoludur; SwiftTerm linki kendisi açmaz.
    func testPlainClickOnHighlightedLinkDoesNotOpenItThroughSwiftTerm() {
        hover(at: linkPoint())
        view.mouseMoved(with: mouse(.mouseMoved, at: linkPoint()))

        view.mouseDown(with: mouse(.leftMouseDown, at: linkPoint()))
        view.mouseUp(with: mouse(.leftMouseUp, at: linkPoint()))

        XCTAssertTrue(spy.openedLinks.isEmpty, "SwiftTerm linki popover'ın yanında ayrıca açtı")
        XCTAssertEqual(activations, [Self.link])
    }

    /// Hover'da diskte olmadığı görülen yolun düz tıkı popover'a dönüşmez.
    func testClickOnKnownMissingPathIsLeftToTheTerminal() {
        useDisk([])
        hover(at: linkPoint())

        view.mouseDown(with: mouse(.leftMouseDown, at: linkPoint()))
        view.mouseUp(with: mouse(.leftMouseUp, at: linkPoint()))

        XCTAssertTrue(activations.isEmpty)
    }

    /// Diskte görülmemiş çıplak dosya adı tıkla da link sayılmaz.
    func testClickOnUnprobedBareFilenameOpensNothing() {
        show("README.md")
        view.linkPathCache = TerminalLinkPathCache(probe: { _ in true }, runsInline: false)

        view.mouseDown(with: mouse(.leftMouseDown, at: point(column: 1)))
        view.mouseUp(with: mouse(.leftMouseUp, at: point(column: 1)))

        XCTAssertTrue(activations.isEmpty)
    }
}
