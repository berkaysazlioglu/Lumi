import LumiKit
import XCTest
@testable import LumiUI

/// Markdown blok ayrıştırma + diff/doküman satır modeli (karar 21).
final class MarkdownDiffBuilderTests: XCTestCase {
    private func style(_ text: String, insideFence: Bool = false) -> MarkdownDiffBuilder.BlockStyle {
        MarkdownDiffBuilder.parse(text, insideFence: insideFence).style
    }

    private func content(_ text: String, insideFence: Bool = false) -> String {
        MarkdownDiffBuilder.parse(text, insideFence: insideFence).content
    }

    private func line(_ kind: DiffLine.Kind, old: Int?, new: Int?, _ text: String) -> DiffLine {
        DiffLine(kind: kind, oldLineNumber: old, newLineNumber: new, text: text)
    }

    // MARK: - Blok stilleri

    func testHeadingLevelsAndStrippedMarker() {
        XCTAssertEqual(style("# Başlık"), .heading(level: 1))
        XCTAssertEqual(content("### Alt başlık"), "Alt başlık")
        XCTAssertEqual(style("###### Altıncı"), .heading(level: 6))
    }

    func testSevenHashesIsNotHeading() {
        XCTAssertEqual(style("####### too deep"), .paragraph)
    }

    func testHashWithoutSpaceIsParagraph() {
        XCTAssertEqual(style("#tag"), .paragraph)
        XCTAssertEqual(content("#tag"), "#tag")
    }

    func testBulletMarkersAndIndentLevels() {
        XCTAssertEqual(style("- madde"), .bullet(indent: 0))
        XCTAssertEqual(style("* madde"), .bullet(indent: 0))
        XCTAssertEqual(style("  + iç madde"), .bullet(indent: 1))
        XCTAssertEqual(style("        derin"), .paragraph) // liste işareti yok
        XCTAssertEqual(style("        - çok derin"), .bullet(indent: 4)) // sınır kademede durur
        XCTAssertEqual(content("- madde"), "madde")
    }

    func testOrderedListMarkerIsNormalized() {
        XCTAssertEqual(style("1. ilk"), .ordered(indent: 0, marker: "1."))
        XCTAssertEqual(style("12) on iki"), .ordered(indent: 0, marker: "12."))
        XCTAssertEqual(content("1. ilk"), "ilk")
        XCTAssertEqual(style("2026 yılında"), .paragraph) // nokta/parantez yok
    }

    func testQuoteRuleTableAndBlank() {
        XCTAssertEqual(style("> alıntı"), .quote)
        XCTAssertEqual(content("> alıntı"), "alıntı")
        XCTAssertEqual(style("---"), .rule)
        XCTAssertEqual(style("***"), .rule)
        XCTAssertEqual(style("--"), .paragraph) // 3'ten az
        XCTAssertEqual(style("| a | b |"), .table)
        XCTAssertEqual(style("   "), .blank)
    }

    func testFenceLineIsFenceAndInsideFenceStaysCode() {
        XCTAssertEqual(style("```swift"), .fence)
        XCTAssertEqual(style("~~~"), .fence)
        // Fence içinde markdown yorumlanmaz: "# yorum" başlık DEĞİLDİR
        XCTAssertEqual(style("# yorum", insideFence: true), .code)
        // Kod satırının girintisi korunur
        XCTAssertEqual(content("    let a = 1", insideFence: true), "    let a = 1")
    }

    // MARK: - Diff dönüşümü

    func testBinaryProducesNoRows() {
        let model = MarkdownDiffBuilder.build(
            UnifiedDiff(filePath: "a.md", isBinary: true, hunks: [])
        )
        XCTAssertTrue(model.isBinary)
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testBuildKeepsHunkHeaderKindsAndLineNumbers() {
        let diff = UnifiedDiff(filePath: "a.md", isBinary: false, hunks: [
            DiffHunk(header: "@@ -1,2 +1,2 @@", lines: [
                line(.context, old: 1, new: 1, "# Lumi"),
                line(.deletion, old: 2, new: nil, "- eski madde"),
                line(.addition, old: nil, new: 2, "- yeni madde"),
            ]),
        ])

        let model = MarkdownDiffBuilder.build(diff)

        XCTAssertEqual(model.rows.first, .hunk("@@ -1,2 +1,2 @@"))
        XCTAssertEqual(model.rows, [
            .hunk("@@ -1,2 +1,2 @@"),
            .line(.init(kind: .context, oldLineNumber: 1, newLineNumber: 1,
                        style: .heading(level: 1), content: "Lumi")),
            .line(.init(kind: .deletion, oldLineNumber: 2, newLineNumber: nil,
                        style: .bullet(indent: 0), content: "eski madde")),
            .line(.init(kind: .addition, oldLineNumber: nil, newLineNumber: 2,
                        style: .bullet(indent: 0), content: "yeni madde")),
        ])
    }

    func testFenceStateResetsPerHunk() {
        // İlk hunk'ta açılan fence kapanmadan bitiyor; ikinci hunk temiz başlar.
        let diff = UnifiedDiff(filePath: "a.md", isBinary: false, hunks: [
            DiffHunk(header: "@@ -1,2 +1,2 @@", lines: [
                line(.context, old: 1, new: 1, "```swift"),
                line(.addition, old: nil, new: 2, "let a = 1"),
            ]),
            DiffHunk(header: "@@ -9,1 +9,1 @@", lines: [
                line(.context, old: 9, new: 9, "## Bölüm"),
            ]),
        ])

        let model = MarkdownDiffBuilder.build(diff)

        guard case .line(let fenced) = model.rows[2] else { return XCTFail("satır beklendi") }
        XCTAssertEqual(fenced.style, .code)
        guard case .line(let secondHunkLine) = model.rows[4] else { return XCTFail("satır beklendi") }
        XCTAssertEqual(secondHunkLine.style, .heading(level: 2))
    }

    func testBuildDocumentNumbersEveryLineAsContext() {
        let model = MarkdownDiffBuilder.buildDocument("# Başlık\n\n- madde\n")

        XCTAssertEqual(model.rows.count, 4) // sondaki \n boş satır üretir
        XCTAssertEqual(model.rows, [
            .line(.init(kind: .context, oldLineNumber: nil, newLineNumber: 1,
                        style: .heading(level: 1), content: "Başlık")),
            .line(.init(kind: .context, oldLineNumber: nil, newLineNumber: 2,
                        style: .blank, content: "")),
            .line(.init(kind: .context, oldLineNumber: nil, newLineNumber: 3,
                        style: .bullet(indent: 0), content: "madde")),
            .line(.init(kind: .context, oldLineNumber: nil, newLineNumber: 4,
                        style: .blank, content: "")),
        ])
    }

    // MARK: - Satır-içi markdown

    func testInlineMarkdownStripsMarkersAndKeepsIntents() {
        let attributed = MarkdownDiffBuilder.inlineAttributed("**kalın** ve `kod`")

        XCTAssertEqual(String(attributed.characters), "kalın ve kod")
        let hasStrong = attributed.runs.contains {
            $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        let hasCode = attributed.runs.contains {
            $0.inlinePresentationIntent?.contains(.code) == true
        }
        XCTAssertTrue(hasStrong)
        XCTAssertTrue(hasCode)
    }

    func testInlineMarkdownPreservesLinkText() {
        let attributed = MarkdownDiffBuilder.inlineAttributed("bkz [tasarım](docs/design.md)")

        XCTAssertEqual(String(attributed.characters), "bkz tasarım")
        XCTAssertTrue(attributed.runs.contains { $0.link != nil })
    }

    func testEmptyInlineTextIsEmptyAttributedString() {
        XCTAssertTrue(String(MarkdownDiffBuilder.inlineAttributed("").characters).isEmpty)
    }
}
