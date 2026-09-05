import LumiKit
import XCTest

final class ExplorerContentQueryTests: XCTestCase {
    func testPlainTextIsEscapedAndCaseInsensitiveByDefault() throws {
        let regex = try ExplorerContentQuery(text: "a.b").regularExpression()
        XCTAssertNotNil(regex.firstMatch(in: "xA.By", range: NSRange(location: 0, length: 5)))
        XCTAssertNil(regex.firstMatch(in: "aXb", range: NSRange(location: 0, length: 3)))
    }

    func testCaseSensitiveRejectsDifferentCase() throws {
        let regex = try ExplorerContentQuery(text: "Theme", isCaseSensitive: true).regularExpression()
        XCTAssertNil(regex.firstMatch(in: "theme", range: NSRange(location: 0, length: 5)))
    }

    func testWholeWordWrapsWordBoundaries() throws {
        let regex = try ExplorerContentQuery(text: "row", isWholeWord: true).regularExpression()
        XCTAssertNil(regex.firstMatch(in: "rows", range: NSRange(location: 0, length: 4)))
        XCTAssertNotNil(regex.firstMatch(in: "a row b", range: NSRange(location: 0, length: 7)))
    }

    func testRegexModeUsesPatternAndReportsInvalidPattern() throws {
        let regex = try ExplorerContentQuery(text: "fo+", isRegex: true).regularExpression()
        XCTAssertNotNil(regex.firstMatch(in: "foo", range: NSRange(location: 0, length: 3)))
        XCTAssertThrowsError(try ExplorerContentQuery(text: "(", isRegex: true).regularExpression()) {
            XCTAssertEqual($0 as? ExplorerContentQuery.QueryError, .invalidRegex("("))
        }
    }

    func testGlobMatchesBasenameWhenPatternHasNoSlash() {
        XCTAssertTrue(ExplorerGlob.matches("*.swift", path: "Sources/App/Main.swift"))
        XCTAssertFalse(ExplorerGlob.matches("*.swift", path: "Sources/App/Main.ts"))
    }

    func testGlobWithSlashMatchesFullPath() {
        XCTAssertTrue(ExplorerGlob.matches("Sources/**", path: "Sources/App/Main.swift"))
        XCTAssertTrue(ExplorerGlob.matches("**/*.min.js", path: "dist/app.min.js"))
        XCTAssertTrue(ExplorerGlob.matches("**/*.min.js", path: "app.min.js"))
        XCTAssertFalse(ExplorerGlob.matches("Sources/*", path: "Sources/App/Main.swift"))
    }

    func testIncludeAndExcludeFilters() {
        let query = ExplorerContentQuery(text: "x", includePatterns: "*.swift, Docs/**", excludePatterns: "*Tests.swift")
        XCTAssertTrue(query.includes(path: "Sources/A.swift"))
        XCTAssertTrue(query.includes(path: "Docs/readme.md"))
        XCTAssertFalse(query.includes(path: "Sources/ATests.swift"))
        XCTAssertFalse(query.includes(path: "Package.resolved"))
        XCTAssertTrue(ExplorerContentQuery(text: "x").includes(path: "anything.bin"))
    }

    func testMatchPreviewUsesReportedColumn() {
        let match = ExplorerContentMatch(path: "a", line: 1, text: "let Row = row", column: 10, length: 3)
        let preview = ExplorerMatchPreview.make(match, query: "row")
        XCTAssertEqual(preview.before, "let Row = ")
        XCTAssertEqual(preview.match, "row")
        XCTAssertEqual(preview.after, "")
    }
}
