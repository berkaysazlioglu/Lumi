import XCTest
@testable import LumiKit

/// Terminal aramasının saf kuralları (karar 144): eşleştirici, sayaç metni,
/// etkin eşleşme seçimi.
final class TerminalSearchTests: XCTestCase {
    private func ranges(_ line: String, _ query: TerminalSearchQuery, limit: Int = 1000) -> [Range<Int>] {
        guard let compiled = TerminalSearchMatcher.compile(query) else { return [] }
        return TerminalSearchMatcher.ranges(in: line, compiled: compiled, limit: limit)
    }

    // MARK: - Eşleştirici

    func testLiteralIsCaseInsensitiveByDefault() {
        XCTAssertEqual(ranges("Foo foo FOO", TerminalSearchQuery(text: "foo")), [0 ..< 3, 4 ..< 7, 8 ..< 11])
        XCTAssertEqual(ranges("Foo foo FOO", TerminalSearchQuery(text: "foo", isCaseSensitive: true)), [4 ..< 7])
    }

    func testLiteralMatchesDoNotOverlap() {
        XCTAssertEqual(ranges("aaaa", TerminalSearchQuery(text: "aa")), [0 ..< 2, 2 ..< 4])
    }

    func testLiteralTreatsRegexCharactersLiterally() {
        XCTAssertEqual(ranges("a.b axb", TerminalSearchQuery(text: "a.b")), [0 ..< 3])
    }

    func testRegexMatchesAndSkipsEmptyMatches() {
        XCTAssertEqual(ranges("a1 b22", TerminalSearchQuery(text: "\\d+", isRegex: true)), [1 ..< 2, 4 ..< 6])
        XCTAssertEqual(ranges("xyz", TerminalSearchQuery(text: "a*", isRegex: true)), [])
    }

    func testInvalidRegexAndEmptyQueryDoNotCompile() {
        XCTAssertNil(TerminalSearchMatcher.compile(TerminalSearchQuery(text: "(", isRegex: true)))
        XCTAssertNil(TerminalSearchMatcher.compile(TerminalSearchQuery(text: "")))
    }

    func testOversizedQueryIsNotRequested() {
        let query = TerminalSearchQuery(text: String(repeating: "a", count: TerminalSearchQuery.maxBytes + 1))
        XCTAssertTrue(query.isTooLarge)
        XCTAssertNil(query.requestText)
        XCTAssertNotNil(TerminalSearchQuery(text: String(repeating: "a", count: TerminalSearchQuery.maxBytes)).requestText)
    }

    func testLimitStopsTheScan() {
        XCTAssertEqual(ranges("a a a a", TerminalSearchQuery(text: "a"), limit: 2).count, 2)
    }

    func testRangesAreUTF16Offsets() {
        XCTAssertEqual(ranges("🙂 hit", TerminalSearchQuery(text: "hit")), [3 ..< 6])
    }

    // MARK: - Sayaç (Orca)

    func testStatusText() {
        XCTAssertEqual(TerminalSearchSummary.empty.statusText(hasQuery: false), "0/0")
        XCTAssertEqual(TerminalSearchSummary.empty.statusText(hasQuery: true), "No results")
        XCTAssertEqual(TerminalSearchSummary(activeIndex: 2, count: 14).statusText(hasQuery: true), "3/14")
        XCTAssertEqual(
            TerminalSearchSummary(activeIndex: 0, count: 1000, isCapped: true).statusText(hasQuery: true),
            "1/1000+"
        )
    }

    // MARK: - Etkin eşleşme seçimi

    private let positions = [
        TerminalSearchPosition(row: 2, col: 0),
        TerminalSearchPosition(row: 10, col: 4),
        TerminalSearchPosition(row: 10, col: 9),
        TerminalSearchPosition(row: 40, col: 1),
    ]

    private func select(_ step: TerminalSearchStep, active: TerminalSearchPosition?, visible: ClosedRange<Int>) -> Int? {
        TerminalSearchNavigation.select(step, positions: positions, active: active, visibleRows: visible)
    }

    func testWithoutActiveMatchTheFirstVisibleWins() {
        XCTAssertEqual(select(.incremental, active: nil, visible: 8 ... 20), 1)
    }

    func testWithoutVisibleMatchTheNearestAboveWins() {
        XCTAssertEqual(select(.incremental, active: nil, visible: 20 ... 30), 2)
        XCTAssertEqual(select(.next, active: nil, visible: 0 ... 1), 0, "üstte yoksa alttaki ilk")
    }

    func testNextAndPreviousWrap() {
        XCTAssertEqual(select(.next, active: positions[3], visible: 0 ... 50), 0)
        XCTAssertEqual(select(.previous, active: positions[0], visible: 0 ... 50), 3)
        XCTAssertEqual(select(.next, active: positions[1], visible: 0 ... 50), 2)
        XCTAssertEqual(select(.previous, active: positions[2], visible: 0 ... 50), 1)
    }

    func testIncrementalStaysOnTheActiveMatchOrMovesForward() {
        XCTAssertEqual(select(.incremental, active: positions[1], visible: 0 ... 50), 1)
        XCTAssertEqual(select(.incremental, active: TerminalSearchPosition(row: 11, col: 0), visible: 0 ... 50), 3)
    }

    func testNoMatchesSelectsNothing() {
        XCTAssertNil(TerminalSearchNavigation.select(.next, positions: [], active: nil, visibleRows: 0 ... 10))
    }
}
