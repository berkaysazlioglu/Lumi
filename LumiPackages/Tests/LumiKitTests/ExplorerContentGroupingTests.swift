import XCTest
@testable import LumiKit

/// İçerik arama sonuçlarının dosya bazlı gruplanması ve satır önizlemesi.
final class ExplorerContentGroupingTests: XCTestCase {
    private func match(_ path: String, _ line: Int, _ text: String = "hit") -> ExplorerContentMatch {
        ExplorerContentMatch(path: path, line: line, text: text)
    }

    // MARK: - Gruplama

    func testMatchesAreGroupedByFileInFirstSeenOrder() {
        let result = ExplorerContentResult(matches: [
            match("b.swift", 1), match("a.swift", 4), match("b.swift", 9),
        ])
        let groups = result.fileGroups
        XCTAssertEqual(groups.map(\.path), ["b.swift", "a.swift"])
        XCTAssertEqual(groups[0].matches.map(\.line), [1, 9])
        XCTAssertEqual(groups[1].matches.map(\.line), [4])
    }

    func testEmptyResultProducesNoGroups() {
        XCTAssertTrue(ExplorerContentResult().fileGroups.isEmpty)
    }

    func testGroupSplitsNameAndDirectory() {
        let group = ExplorerContentResult(matches: [match("Sources/LumiUI/Theme.swift", 2)]).fileGroups[0]
        XCTAssertEqual(group.name, "Theme.swift")
        XCTAssertEqual(group.directory, "Sources/LumiUI")
    }

    func testRootLevelFileHasEmptyDirectory() {
        let group = ExplorerContentResult(matches: [match("README.md", 1)]).fileGroups[0]
        XCTAssertEqual(group.name, "README.md")
        XCTAssertEqual(group.directory, "")
    }

    // MARK: - Satır önizlemesi

    func testPreviewSplitsAroundTheMatch() {
        let preview = ExplorerMatchPreview.make(text: "let value = compute()", query: "compute")
        XCTAssertEqual(preview.before, "let value = ")
        XCTAssertEqual(preview.match, "compute")
        XCTAssertEqual(preview.after, "()")
    }

    func testPreviewMatchesCaseInsensitivelyButKeepsOriginalText() {
        let preview = ExplorerMatchPreview.make(text: "Theme.Radius", query: "radius")
        XCTAssertEqual(preview.match, "Radius")
    }

    func testLongPrefixIsLeftTruncatedWithEllipsis() {
        let text = String(repeating: "x", count: 60) + "needle"
        let preview = ExplorerMatchPreview.make(text: text, query: "needle")
        XCTAssertTrue(preview.before.hasPrefix("…"))
        XCTAssertEqual(preview.before.count, ExplorerMatchPreview.prefixLimit + 1)
        XCTAssertEqual(preview.match, "needle")
    }

    func testLeadingIndentationIsTrimmed() {
        let preview = ExplorerMatchPreview.make(text: "        return value", query: "return")
        XCTAssertEqual(preview.before, "")
    }

    func testMissingQueryFallsBackToWholeLine() {
        let preview = ExplorerMatchPreview.make(text: "no hit here", query: "zzz")
        XCTAssertEqual(preview.before, "no hit here")
        XCTAssertTrue(preview.match.isEmpty)
        XCTAssertTrue(preview.after.isEmpty)
    }

    func testEmptyQueryFallsBackToWholeLine() {
        let preview = ExplorerMatchPreview.make(text: "line", query: "")
        XCTAssertEqual(preview.before, "line")
        XCTAssertTrue(preview.match.isEmpty)
    }
}
