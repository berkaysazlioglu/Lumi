import LumiKit
import XCTest
@testable import LumiServices

/// Karar 109: cmark-gfm ağacının LumiKit modeline birebir inmesi.
final class SwiftMarkdownParserTests: XCTestCase {
    private let parser = SwiftMarkdownParser()

    private func blocks(_ text: String) -> [MarkdownBlock] {
        parser.parse(text).blocks
    }

    func testTableKeepsHeaderRowsAndAlignment() {
        // Kullanıcı raporundaki tablo: raw `|` satırları olarak görünüyordu.
        let text = """
        | # | Finding | Value |
        |---|:---:|---:|
        | C1 | No constructor or type injection | High |
        | C2 | No `collection` injection |
        """
        guard case .table(let table) = blocks(text).first else {
            return XCTFail("tablo ayrıştırılmalı")
        }
        XCTAssertEqual(table.alignments, [.leading, .center, .trailing])
        XCTAssertEqual(table.header.map(\.plainText), ["#", "Finding", "Value"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0].map(\.plainText), ["C1", "No constructor or type injection", "High"])
        // Eksik hücre boş içerikle tamamlanır; satır-içi kod korunur.
        XCTAssertEqual(table.rows[1].count, 3)
        XCTAssertEqual(table.rows[1][1], [.text("No "), .code("collection"), .text(" injection")])
        XCTAssertEqual(table.rows[1][2], [])
    }

    func testSoftWrappedLinesJoinIntoOneParagraph() {
        let text = "First line\nsecond line\n\nNext paragraph"
        XCTAssertEqual(blocks(text), [
            .paragraph([.text("First line"), .softBreak, .text("second line")]),
            .paragraph([.text("Next paragraph")]),
        ])
    }

    func testHeadingAndInlineStyles() {
        let text = "## Summary **bold** *it* ~~old~~ [link](https://x.dev)"
        XCTAssertEqual(blocks(text), [
            .heading(level: 2, content: [
                .text("Summary "),
                .strong([.text("bold")]),
                .text(" "),
                .emphasis([.text("it")]),
                .text(" "),
                .strikethrough([.text("old")]),
                .text(" "),
                .link(destination: "https://x.dev", content: [.text("link")]),
            ]),
        ])
    }

    func testNestedAndTaskLists() {
        let text = """
        3. three
           - [x] done
           - [ ] open
        4. four
        """
        guard case .list(let list) = blocks(text).first else { return XCTFail("liste bekleniyordu") }
        XCTAssertEqual(list.startIndex, 3)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].blocks.first, .paragraph([.text("three")]))
        guard case .list(let nested) = list.items[0].blocks.last else { return XCTFail("iç liste bekleniyordu") }
        XCTAssertFalse(nested.isOrdered)
        XCTAssertEqual(nested.items.map(\.checkbox), [true, false])
        XCTAssertNil(list.items[1].checkbox)
    }

    func testFencedCodeBlockKeepsLanguageAndContent() {
        let text = """
        ```swift title="x"
        let a = 1
        let b = 2
        ```
        """
        XCTAssertEqual(blocks(text), [.codeBlock(language: "swift", code: "let a = 1\nlet b = 2")])
    }

    func testQuoteRuleAndHTML() {
        let text = "> quoted\n\n---\n\n<details>\n<summary>x</summary>\n</details>"
        XCTAssertEqual(blocks(text), [
            .blockQuote([.paragraph([.text("quoted")])]),
            .thematicBreak,
            .html("<details>\n<summary>x</summary>\n</details>"),
        ])
    }

    func testImageCarriesAltAndSource() {
        XCTAssertEqual(blocks("![logo **big**](img/logo.png)"), [
            .paragraph([.image(source: "img/logo.png", alt: "logo big")]),
        ])
    }

    func testHardLineBreak() {
        XCTAssertEqual(blocks("a  \nb"), [.paragraph([.text("a"), .lineBreak, .text("b")])])
    }
}
