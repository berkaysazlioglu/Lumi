import XCTest
import LumiKit
@testable import LumiServices

final class UnifiedDiffParserTests: XCTestCase {
    func testBasicHunkWithLineNumbers() {
        let raw = """
        diff --git a/file.txt b/file.txt
        index 0000000..1111111 100644
        --- a/file.txt
        +++ b/file.txt
        @@ -2,3 +2,4 @@ context header
         unchanged
        -removed line
        +added line
        +another added
        """
        let diff = UnifiedDiffParser.parse(raw, filePath: "file.txt")

        XCTAssertFalse(diff.isBinary)
        XCTAssertEqual(diff.hunks.count, 1)
        let lines = diff.hunks[0].lines
        XCTAssertEqual(lines.count, 4)

        XCTAssertEqual(lines[0].kind, .context)
        XCTAssertEqual(lines[0].oldLineNumber, 2)
        XCTAssertEqual(lines[0].newLineNumber, 2)

        XCTAssertEqual(lines[1].kind, .deletion)
        XCTAssertEqual(lines[1].oldLineNumber, 3)
        XCTAssertNil(lines[1].newLineNumber)

        XCTAssertEqual(lines[2].kind, .addition)
        XCTAssertNil(lines[2].oldLineNumber)
        XCTAssertEqual(lines[2].newLineNumber, 3)

        XCTAssertEqual(lines[3].kind, .addition)
        XCTAssertEqual(lines[3].newLineNumber, 4)
        XCTAssertEqual(lines[3].text, "another added")
    }

    func testMultipleHunks() {
        let raw = """
        @@ -1,2 +1,2 @@
        -a
        +b
        @@ -10,2 +10,2 @@
         x
        -y
        +z
        """
        let diff = UnifiedDiffParser.parse(raw, filePath: "f")
        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertEqual(diff.hunks[1].lines[0].oldLineNumber, 10)
    }

    func testBinaryDetection() {
        let diff = UnifiedDiffParser.parse(
            "Binary files a/img.png and b/img.png differ",
            filePath: "img.png"
        )
        XCTAssertTrue(diff.isBinary)
        XCTAssertTrue(diff.hunks.isEmpty)
    }

    func testNoNewlineMarkerSkipped() {
        let raw = """
        @@ -1 +1 @@
        -old
        \\ No newline at end of file
        +new
        \\ No newline at end of file
        """
        let diff = UnifiedDiffParser.parse(raw, filePath: "f")
        XCTAssertEqual(diff.hunks[0].lines.count, 2)
    }

    func testHunkHeaderVariants() {
        XCTAssertEqual(UnifiedDiffParser.parseHunkHeader("@@ -1 +1 @@")?.old, 1)
        XCTAssertEqual(UnifiedDiffParser.parseHunkHeader("@@ -12,5 +14,6 @@ fn main()")?.new, 14)
        XCTAssertNil(UnifiedDiffParser.parseHunkHeader("not a header"))
    }

    func testEmptyInput() {
        let diff = UnifiedDiffParser.parse("", filePath: "f")
        XCTAssertTrue(diff.isEmpty)
    }
}
