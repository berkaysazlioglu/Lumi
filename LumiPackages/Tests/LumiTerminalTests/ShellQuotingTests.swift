import XCTest
@testable import LumiTerminal

final class ShellQuotingTests: XCTestCase {
    func testPlainPathUnchanged() {
        XCTAssertEqual(ShellQuoting.quote("/usr/local/bin/claude"), "/usr/local/bin/claude")
    }

    func testPathWithSpaceQuoted() {
        XCTAssertEqual(
            ShellQuoting.quote("/Users/dev/My Project/file.txt"),
            "'/Users/dev/My Project/file.txt'"
        )
    }

    func testSingleQuoteEscaped() {
        XCTAssertEqual(
            ShellQuoting.quote("/tmp/it's here.txt"),
            "'/tmp/it'\\''s here.txt'"
        )
    }

    func testTildeIsQuotedAgainstExpansion() {
        XCTAssertEqual(ShellQuoting.quote("~/notes.md"), "'~/notes.md'")
    }

    func testEmptyPathRepresentable() {
        XCTAssertEqual(ShellQuoting.quote(""), "''")
    }

    func testJoinedPaths() {
        XCTAssertEqual(
            ShellQuoting.joinedPaths(["/a/b.txt", "/c d/e.txt"]),
            "/a/b.txt '/c d/e.txt'"
        )
    }
}
