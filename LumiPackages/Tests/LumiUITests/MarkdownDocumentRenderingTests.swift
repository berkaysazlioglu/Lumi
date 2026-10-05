import LumiKit
import SwiftUI
import XCTest
@testable import LumiUI

/// Karar 109: render'lı markdown'ın saf parçaları (sütun paylaşımı, madde
/// işareti, satır-içi stil).
@MainActor
final class MarkdownDocumentRenderingTests: XCTestCase {
    func testColumnsKeepNaturalWidthWhenTableFits() {
        XCTAssertEqual(MarkdownTableColumns.fit(natural: [20, 200, 40], available: 600), [20, 200, 40])
        XCTAssertEqual(MarkdownTableColumns.fit(natural: [20, 200], available: nil), [20, 200])
    }

    func testNarrowColumnsStayNaturalAndWideColumnsShareTheRest() {
        // 400'lük alan: 20 ve 40 adil payın altında kalır; kalan 340 geniş
        // sütunlara doğal genişlikleriyle orantılı (600:200) bölünür.
        let widths = MarkdownTableColumns.fit(natural: [20, 600, 40, 200], available: 400)
        XCTAssertEqual(widths[0], 20)
        XCTAssertEqual(widths[2], 40)
        XCTAssertEqual(widths[1], 255, accuracy: 0.001)
        XCTAssertEqual(widths[3], 85, accuracy: 0.001)
        XCTAssertEqual(widths.reduce(0, +), 400, accuracy: 0.001)
    }

    func testBulletCyclesByDepth() {
        XCTAssertEqual((0..<4).map(MarkdownListMarker.bullet(depth:)), ["•", "◦", "▪", "•"])
    }

    func testInlineRendererKeepsTextAndMarksLinksAndCode() {
        let attributed = MarkdownInlineRenderer.attributed(
            [
                .text("See "),
                .link(destination: "docs/x.md", content: [.strong([.text("docs")])]),
                .softBreak,
                .code("let"),
                .image(source: "a.png", alt: ""),
            ],
            style: .init(size: .base)
        )
        XCTAssertEqual(String(attributed.characters), "See docs let[image]")
        let linked = attributed.runs.compactMap(\.link)
        XCTAssertEqual(linked, [URL(string: "docs/x.md")!])
        XCTAssertTrue(attributed.runs.contains { $0.backgroundColor != nil }, "satır-içi kod zemin taşır")
    }
}
