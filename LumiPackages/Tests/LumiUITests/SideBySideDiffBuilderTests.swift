import LumiKit
import XCTest
@testable import LumiUI

/// UnifiedDiff → side-by-side satır modeli dönüşümü (karar 4 revize).
final class SideBySideDiffBuilderTests: XCTestCase {
    private func line(_ kind: DiffLine.Kind, old: Int?, new: Int?, _ text: String) -> DiffLine {
        DiffLine(kind: kind, oldLineNumber: old, newLineNumber: new, text: text)
    }

    func testBinaryProducesNoRows() {
        let model = SideBySideDiffBuilder.build(
            UnifiedDiff(filePath: "a.png", isBinary: true, hunks: [])
        )
        XCTAssertTrue(model.isBinary)
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testContextAppearsOnBothSidesWithSeparateLineNumbers() {
        let diff = UnifiedDiff(filePath: "f", isBinary: false, hunks: [
            DiffHunk(header: "@@ -1 +1 @@", lines: [line(.context, old: 1, new: 1, "same")]),
        ])
        let model = SideBySideDiffBuilder.build(diff)
        XCTAssertEqual(model.rows, [
            .header("@@ -1 +1 @@"),
            .lines(
                left: .init(lineNumber: 1, text: "same", kind: .context),
                right: .init(lineNumber: 1, text: "same", kind: .context)
            ),
        ])
    }

    func testDeletionAndAdditionPairOnSameRow() {
        // Bir silme + bir ekleme → tek satırda sol eski / sağ yeni (değiştirilmiş)
        let diff = UnifiedDiff(filePath: "f", isBinary: false, hunks: [
            DiffHunk(header: "@@", lines: [
                line(.deletion, old: 5, new: nil, "old line"),
                line(.addition, old: nil, new: 5, "new line"),
            ]),
        ])
        let rows = SideBySideDiffBuilder.build(diff).rows
        XCTAssertEqual(rows.last, .lines(
            left: .init(lineNumber: 5, text: "old line", kind: .deletion),
            right: .init(lineNumber: 5, text: "new line", kind: .addition)
        ))
    }

    func testExtraDeletionGetsEmptyRightFiller() {
        // 2 silme, 1 ekleme → ikinci silmenin sağı filler (nil)
        let diff = UnifiedDiff(filePath: "f", isBinary: false, hunks: [
            DiffHunk(header: "@@", lines: [
                line(.deletion, old: 1, new: nil, "del1"),
                line(.deletion, old: 2, new: nil, "del2"),
                line(.addition, old: nil, new: 1, "add1"),
            ]),
        ])
        let rows = SideBySideDiffBuilder.build(diff).rows
        XCTAssertEqual(rows[1], .lines(
            left: .init(lineNumber: 1, text: "del1", kind: .deletion),
            right: .init(lineNumber: 1, text: "add1", kind: .addition)
        ))
        XCTAssertEqual(rows[2], .lines(
            left: .init(lineNumber: 2, text: "del2", kind: .deletion),
            right: nil
        ))
    }

    func testPureAdditionGetsEmptyLeftFiller() {
        let diff = UnifiedDiff(filePath: "f", isBinary: false, hunks: [
            DiffHunk(header: "@@", lines: [line(.addition, old: nil, new: 10, "added")]),
        ])
        let rows = SideBySideDiffBuilder.build(diff).rows
        XCTAssertEqual(rows.last, .lines(
            left: nil,
            right: .init(lineNumber: 10, text: "added", kind: .addition)
        ))
    }

    func testPairingResetsAtContextBoundary() {
        // Silme bloğu, sonra context → context'ten önce flush; karışmaz
        let diff = UnifiedDiff(filePath: "f", isBinary: false, hunks: [
            DiffHunk(header: "@@", lines: [
                line(.deletion, old: 1, new: nil, "del"),
                line(.context, old: 2, new: 1, "ctx"),
                line(.addition, old: nil, new: 2, "add"),
            ]),
        ])
        let rows = SideBySideDiffBuilder.build(diff).rows
        // header, del(sağ filler), ctx(iki taraf), add(sol filler)
        XCTAssertEqual(rows[1], .lines(
            left: .init(lineNumber: 1, text: "del", kind: .deletion), right: nil
        ))
        XCTAssertEqual(rows[2], .lines(
            left: .init(lineNumber: 2, text: "ctx", kind: .context),
            right: .init(lineNumber: 1, text: "ctx", kind: .context)
        ))
        XCTAssertEqual(rows[3], .lines(
            left: nil, right: .init(lineNumber: 2, text: "add", kind: .addition)
        ))
    }
}
