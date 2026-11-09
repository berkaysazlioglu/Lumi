import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// Terminal arama çubuklarının durumu (karar 144 — Orca `TerminalSearch`).
@MainActor
final class TerminalSearchStoreTests: XCTestCase {
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var engine: FakeTerminalSearch!
    private var store: TerminalSearchStore!
    private var id: TerminalID!

    override func setUp() async throws {
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        engine = FakeTerminalSearch()
        store = TerminalSearchStore(engine: engine, terminals: terminals)
        let meta = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/repo", createdAt: Date())
        terminals.apply(.spawned(meta))
        id = meta.id
    }

    func testOpenShowsTheBarAndRequestsFocus() {
        store.open(id)
        XCTAssertTrue(store.isOpen(id))
        XCTAssertEqual(store.session(for: id)?.focusRequest, 1)
        XCTAssertEqual(store.session(for: id)?.statusText, "0/0")
    }

    func testFocusRequestIsHandledOnce() {
        store.open(id)
        XCTAssertEqual(store.session(for: id)?.isFocusRequested, true)
        store.didFocusField(id)
        XCTAssertEqual(store.session(for: id)?.isFocusRequested, false, "kart yeniden doğunca odak çalınmaz")
        store.open(id)
        XCTAssertEqual(store.session(for: id)?.isFocusRequested, true, "⌘F yeniden ister")
    }

    func testOpenAgainOnlyRefocuses() {
        store.open(id)
        store.setText("err", for: id)
        let calls = engine.calls.count
        store.open(id)
        XCTAssertEqual(store.session(for: id)?.focusRequest, 2)
        XCTAssertEqual(engine.calls.count, calls, "açık çubukta ⌘F aramayı yeniden koşmaz")
    }

    func testTypingRunsAnIncrementalSearch() {
        store.open(id)
        engine.nextSummary = TerminalSearchSummary(activeIndex: 2, count: 14)
        store.setText("error", for: id)
        XCTAssertEqual(engine.calls.last, .init(id: id, query: TerminalSearchQuery(text: "error"), step: .incremental))
        XCTAssertEqual(store.session(for: id)?.statusText, "3/14")
    }

    func testOptionsRerunTheSearch() {
        store.open(id)
        store.setText("x", for: id)
        store.toggleCaseSensitive(id)
        store.toggleRegex(id)
        XCTAssertEqual(engine.calls.last?.query, TerminalSearchQuery(text: "x", isCaseSensitive: true, isRegex: true))
        XCTAssertEqual(engine.calls.last?.step, .incremental)
    }

    func testEnterAndShiftEnterNavigate() {
        store.open(id)
        store.setText("x", for: id)
        store.next(id)
        XCTAssertEqual(engine.calls.last?.step, .next)
        store.previous(id)
        XCTAssertEqual(engine.calls.last?.step, .previous)
    }

    func testCloseClearsHighlightsKeepsQueryAndRefocusesTheTerminal() {
        store.open(id)
        store.setText("needle", for: id)
        store.close(id)
        XCTAssertFalse(store.isOpen(id))
        XCTAssertEqual(engine.clearedIDs, [id])
        XCTAssertEqual(service.focusCalls.last, id)
        XCTAssertEqual(store.session(for: id)?.query.text, "needle")

        store.open(id)
        XCTAssertEqual(engine.calls.last, .init(id: id, query: TerminalSearchQuery(text: "needle"), step: .incremental),
                       "yeniden açılınca aynı sorgu koşar")
    }

    func testClosedBarDoesNotSearch() {
        store.next(id)
        store.setText("x", for: id)
        XCTAssertTrue(engine.calls.isEmpty)
    }

    func testShortcutNavigationNeedsAnOpenBarWithAQueryAndFocusesTheTerminal() {
        store.navigateFromShortcut(id, forward: true)
        XCTAssertTrue(engine.calls.isEmpty)
        store.open(id)
        store.navigateFromShortcut(id, forward: true)
        XCTAssertEqual(engine.calls.count, 1, "sorgusuz ⌘G no-op")

        store.setText("x", for: id)
        store.navigateFromShortcut(id, forward: false)
        XCTAssertEqual(engine.calls.last?.step, .previous)
        XCTAssertEqual(service.focusCalls.last, id)
    }

    func testRecountUpdatesOnlyAnOpenBar() {
        store.open(id)
        store.setText("x", for: id)
        engine.emitRecount(TerminalSearchSummary(activeIndex: 0, count: 3), for: id)
        XCTAssertEqual(store.session(for: id)?.statusText, "1/3")

        store.close(id)
        engine.emitRecount(TerminalSearchSummary(activeIndex: 0, count: 9), for: id)
        XCTAssertEqual(store.session(for: id)?.summary, .empty)
    }

    func testOpeningPrunesExitedTerminals() {
        store.open(id)
        terminals.apply(.exited(id, code: 0))
        let other = TerminalMeta(id: TerminalID(), name: "o", repoPath: "/repo", createdAt: Date())
        terminals.apply(.spawned(other))
        store.open(other.id)
        XCTAssertNil(store.session(for: id))
    }
}
