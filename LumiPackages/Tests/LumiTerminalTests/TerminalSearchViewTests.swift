import AppKit
import LumiKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Terminal içi arama motoru (karar 144) gerçek SwiftTerm buffer'ı üstünde:
/// scrollback taraması, sarılan satır, geniş karakter, vurgular, kaydırma ve
/// çıktı akarken yeniden sayım.
@MainActor
final class TerminalSearchViewTests: XCTestCase {
    private var view: DropAwareTerminalView!

    override func setUp() async throws {
        view = DropAwareTerminalView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 200),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }

    override func tearDown() async throws {
        view = nil
    }

    private var terminal: Terminal { view.getTerminal() }

    private func feedLines(_ count: Int, marking marked: Set<Int>, word: String = "needle") {
        for index in 0 ..< count {
            view.feed(text: marked.contains(index) ? "line \(index) \(word)\r\n" : "line \(index)\r\n")
        }
    }

    private func search(_ text: String, _ step: TerminalSearchStep = .incremental,
                        caseSensitive: Bool = false, regex: Bool = false) -> TerminalSearchSummary {
        view.runSearch(TerminalSearchQuery(text: text, isCaseSensitive: caseSensitive, isRegex: regex), step: step)
    }

    // MARK: - Tarama

    func testCountsMatchesInScrollbackAndPrefersTheVisibleOne() {
        feedLines(100, marking: [5, 95])
        let summary = search("needle")
        XCTAssertEqual(summary.count, 2)
        // Görünür alan buffer'ın sonudur: önce oradaki eşleşme seçilir.
        XCTAssertEqual(summary.activeIndex, 1)
        XCTAssertEqual(view.searchHighlightSpans.filter(\.isActive).count, 1)
    }

    func testNextWrapsAndScrollsTheMatchIntoView() {
        feedLines(100, marking: [5, 95])
        _ = search("needle")
        let bottom = terminal.buffer.yDisp
        let summary = search("needle", .next)
        XCTAssertEqual(summary.activeIndex, 0, "son eşleşmeden sonra başa sarar")
        XCTAssertLessThan(terminal.buffer.yDisp, bottom, "eşleşmeye kaydırıldı")
        let visible = TerminalSearchBuffer.visibleRows(of: terminal)
        XCTAssertTrue(visible.contains(terminal.buffer.totalLinesTrimmed + 5))
        XCTAssertTrue(view.searchHighlightSpans.contains { $0.isActive })
    }

    func testPreviousWrapsToTheLastMatch() {
        // İki eşleşme de görünür alanda: önce ilk görünen seçilir.
        feedLines(5, marking: [1, 3])
        XCTAssertEqual(search("needle").activeIndex, 0)
        XCTAssertEqual(search("needle", .previous).activeIndex, 1)
    }

    func testIncrementalKeepsTheActiveMatchWhileTyping() {
        feedLines(20, marking: [2, 4])
        _ = search("need")
        let first = search("need", .next)
        XCTAssertEqual(search("needle").activeIndex, first.activeIndex)
    }

    func testCaseSensitivityAndRegex() {
        view.feed(text: "Needle needle NEEDLE\r\n")
        XCTAssertEqual(search("needle").count, 3)
        XCTAssertEqual(search("needle", caseSensitive: true).count, 1)
        XCTAssertEqual(search("n[e]+dle", regex: true).count, 3)
        XCTAssertEqual(search("(", regex: true), .empty, "geçersiz regex eşleşmesiz")
    }

    func testMatchAcrossASoftWrapSpansTwoRows() {
        let cols = terminal.cols
        // "needle" sarma sınırını ortadan keser: ilk 3 harf satır sonunda.
        let text = String(repeating: "x", count: cols - 3) + "needle"
        view.feed(text: text + "\r\n")
        let summary = search("needle")
        XCTAssertEqual(summary.count, 1)
        let spans = view.searchHighlightSpans
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans.first?.columns, cols - 3 ..< cols)
        XCTAssertEqual(spans.last?.columns, 0 ..< 3)
    }

    func testWideCharactersMapToTheirCells() {
        view.feed(text: "日本 needle\r\n")
        _ = search("needle")
        // İki geniş karakter 4 hücre + boşluk.
        XCTAssertEqual(view.searchHighlightSpans.first?.columns, 5 ..< 11)
    }

    func testEmptyOrOversizedQueryClearsTheSearch() {
        view.feed(text: "needle\r\n")
        _ = search("needle")
        XCTAssertEqual(search(""), .empty)
        XCTAssertTrue(view.searchHighlightSpans.isEmpty)
        let oversized = String(repeating: "a", count: TerminalSearchQuery.maxBytes + 1)
        XCTAssertEqual(search(oversized), .empty)
    }

    func testMatchLimitCapsTheCount() {
        let perLine = 50
        for _ in 0 ..< (TerminalSearchMatcher.matchLimit / perLine) + 2 {
            view.feed(text: String(repeating: "a ", count: perLine) + "\r\n")
        }
        let summary = search("a")
        XCTAssertEqual(summary.count, TerminalSearchMatcher.matchLimit)
        XCTAssertTrue(summary.isCapped)
    }

    // MARK: - Canlı içerik

    func testOutputRecountIsReportedAfterTheThrottle() async throws {
        feedLines(5, marking: [1])
        XCTAssertEqual(search("needle").count, 1)
        var reported: [TerminalSearchSummary] = []
        view.onSearchResultsChanged = { reported.append($0) }
        view.feed(text: "more needle\r\n")
        view.noteSearchContentChanged()
        XCTAssertTrue(reported.isEmpty, "sayım kısılır, hemen yapılmaz")
        try await Task.sleep(for: DropAwareTerminalView.searchRescanInterval + .milliseconds(200))
        XCTAssertEqual(reported.last?.count, 2)
        XCTAssertEqual(reported.last?.activeIndex, 0, "etkin eşleşme yerinde kalır")
    }

    func testEndedSearchIgnoresOutput() async throws {
        feedLines(5, marking: [1])
        _ = search("needle")
        view.endSearch()
        var reported = false
        view.onSearchResultsChanged = { _ in reported = true }
        view.feed(text: "needle\r\n")
        view.noteSearchContentChanged()
        try await Task.sleep(for: DropAwareTerminalView.searchRescanInterval + .milliseconds(200))
        XCTAssertFalse(reported)
        XCTAssertTrue(view.searchHighlightSpans.isEmpty)
    }

    func testHighlightsFollowScrolling() {
        feedLines(100, marking: [95])
        _ = search("needle")
        XCTAssertFalse(view.searchHighlightSpans.isEmpty)
        view.scrollTo(row: 0)
        // Üretimde `TerminalSession`'ın `scrolled` delegate'i iletir.
        view.noteSearchViewportChanged()
        XCTAssertTrue(view.searchHighlightSpans.isEmpty, "eşleşme görünür alanın dışına çıktı")
    }

    // MARK: - Registry

    func testRegistryRoutesSearchToTheRegisteredView() {
        let registry = TerminalViewRegistry()
        let id = TerminalID()
        registry.register(view: view, for: id, onVisibilityChange: { _ in })
        view.feed(text: "needle\r\n")
        let summary = registry.search(id, query: TerminalSearchQuery(text: "needle"), step: .incremental)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(registry.search(TerminalID(), query: TerminalSearchQuery(text: "needle"), step: .next), .empty)
        registry.clearSearch(id)
        XCTAssertTrue(view.searchHighlightSpans.isEmpty)
    }
}
