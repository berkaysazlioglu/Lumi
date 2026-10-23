import XCTest
@testable import LumiMobileKit

final class TUIMarkdownTests: XCTestCase {
    func testBlocksCoverHeadingsListsQuotesRulesAndCode() {
        let text = """
        # Plan
        Two **steps**:

        - read `ProjectTree.swift`
          and its tests
        - run tests
        1. first
        2) second

        > note line

        ---
        ```swift
        let a = 1
        ```
        """
        XCTAssertEqual(tuiMarkdownBlocks(text), [
            .heading(level: 1, text: "Plan"),
            .paragraph("Two **steps**:"),
            .listItem(depth: 0, marker: "-", text: "read `ProjectTree.swift`\nand its tests"),
            .listItem(depth: 0, marker: "-", text: "run tests"),
            .listItem(depth: 0, marker: "1.", text: "first"),
            .listItem(depth: 0, marker: "2.", text: "second"),
            .quote("note line"),
            .rule,
            .code(language: "swift", body: "let a = 1"),
        ])
    }

    func testNestedListDepthAndHashWithoutSpaceIsProse() {
        XCTAssertEqual(tuiMarkdownBlocks("- a\n  - b\n#tag"), [
            .listItem(depth: 0, marker: "-", text: "a"),
            .listItem(depth: 1, marker: "-", text: "b"),
            .paragraph("#tag"),
        ])
    }

    func testUnterminatedFenceIsStillCode() {
        XCTAssertEqual(tuiMarkdownBlocks("text\n```\nstreaming"), [
            .paragraph("text"),
            .code(language: nil, body: "streaming"),
        ])
    }

    func testTableParsesAndDrawsAlignedBox() {
        let blocks = tuiMarkdownBlocks("| Name | Size |\n|---|--:|\n| `a.swift` | 12 |\n| b |")
        XCTAssertEqual(blocks, [.table(header: ["Name", "Size"], rows: [["`a.swift`", "12"], ["b"]])])
        XCTAssertEqual(tuiTableLines(header: ["Name", "Size"], rows: [["`a.swift`", "12"], ["b"]]), [
            "┌─────────┬──────┐",
            "│ Name    │ Size │",
            "├─────────┼──────┤",
            "│ a.swift │ 12   │",
            "│ b       │      │",
            "└─────────┴──────┘",
        ])
    }

    func testFoldedOutputKeepsFirstLinesAndCountsTheRest() {
        let folded = TUIFoldedOutput("1\n2\n3\n4\n5\n\n", limit: 3)
        XCTAssertEqual(folded.visible, "1\n2\n3")
        XCTAssertEqual(folded.hiddenLineCount, 2)
        XCTAssertEqual(TUIFoldedOutput("ok", limit: 3).hiddenLineCount, 0)
    }
}
