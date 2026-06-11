import Foundation
import XCTest
import LumiKit
@testable import LumiUI

/// spec/20 §13 grid matematiği birebir testleri.
final class GridLayoutMathTests: XCTestCase {
    private func layout(_ mode: GridLayout.Mode, _ count: Int = 2) -> GridLayout {
        GridLayout(mode: mode, count: count)
    }

    // MARK: - Kolon sayısı

    func testAutoColumnCountFormula() {
        // floor((w + 12) / (400 + 12))
        XCTAssertEqual(
            GridLayoutMath.columnCount(layout: layout(.auto), containerWidth: 1236, visibleCount: 6),
            3
        )
        XCTAssertEqual(
            GridLayoutMath.columnCount(layout: layout(.auto), containerWidth: 400, visibleCount: 6),
            1
        )
        XCTAssertEqual(
            GridLayoutMath.columnCount(layout: layout(.auto), containerWidth: 0, visibleCount: 6),
            1,
            "ölçülmemiş container'da min 1 kolon"
        )
    }

    func testColumnsModeFixedCount() {
        XCTAssertEqual(
            GridLayoutMath.columnCount(layout: layout(.columns, 4), containerWidth: 500, visibleCount: 2),
            4
        )
    }

    func testRowsModeColumnFormula() {
        // cols = ceil(görünür / N)
        XCTAssertEqual(
            GridLayoutMath.columnCount(layout: layout(.rows, 2), containerWidth: 1000, visibleCount: 5),
            3
        )
        XCTAssertEqual(
            GridLayoutMath.columnCount(layout: layout(.rows, 3), containerWidth: 1000, visibleCount: 2),
            1
        )
    }

    // MARK: - Son satır stretch (spec/20 §13 örneği)

    func testStretchDistributionFiveColumnsTwoRemainder() {
        // 5 kolonda 2 artık kart → span 2 ve span 3 (fazla kolon SONDAKİNE)
        let spans = GridLayoutMath.spans(visibleCount: 7, columns: 5, stretchLastRow: true)
        XCTAssertEqual(Array(spans[0..<5]), [1, 1, 1, 1, 1])
        XCTAssertEqual(Array(spans[5...]), [2, 3])
    }

    func testStretchEvenDivisionNoChange() {
        let spans = GridLayoutMath.spans(visibleCount: 6, columns: 3, stretchLastRow: true)
        XCTAssertEqual(spans, [1, 1, 1, 1, 1, 1])
    }

    func testAutoModeNeverStretches() {
        let spans = GridLayoutMath.spans(visibleCount: 4, columns: 3, stretchLastRow: false)
        XCTAssertEqual(spans, [1, 1, 1, 1])
    }

    // MARK: - Frame hesapları

    func testColumnsModeWidths() {
        // floor((1000 - 2*12) / 3) = 325
        let frames = GridLayoutMath.frames(
            layout: layout(.columns, 3),
            container: CGSize(width: 1000, height: 800),
            visibleCount: 3
        )
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].width, 325)
        XCTAssertEqual(frames[1].minX, 337) // 325 + 12
        XCTAssertEqual(frames[2].minX, 674)
        XCTAssertEqual(frames.map(\.minY), [0, 0, 0])
    }

    func testRowsModeFitsViewportWithoutScroll() {
        // rows 2, görünür 4 → cols 2; rowHeight = floor((800-12)/2) = 394
        let frames = GridLayoutMath.frames(
            layout: layout(.rows, 2),
            container: CGSize(width: 1000, height: 800),
            visibleCount: 4
        )
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[0].height, 394)
        XCTAssertEqual(frames[2].minY, 406) // 394 + 12
        XCTAssertEqual(GridLayoutMath.contentHeight(frames: frames), 800)
    }

    func testStretchedLastRowFillsWidth() {
        // columns 5, görünür 7: son satırda span 2 + span 3 tüm genişliği doldurur
        let frames = GridLayoutMath.frames(
            layout: layout(.columns, 5),
            container: CGSize(width: 1072, height: 800),
            visibleCount: 7
        )
        let columnWidth = floor((1072 - 4 * 12) / 5.0) // 204
        XCTAssertEqual(frames[5].width, columnWidth * 2 + 12)
        XCTAssertEqual(frames[6].width, columnWidth * 3 + 2 * 12)
        XCTAssertEqual(frames[6].maxX, frames[4].maxX, accuracy: 0.5, "son satır tüm genişliği doldurmalı")
        XCTAssertEqual(frames[5].minY, frames[6].minY)
        XCTAssertGreaterThan(frames[5].minY, frames[0].minY)
    }

    func testAutoModeLastRowNotStretched() {
        // auto 3 kolon (1236px), 4 görünür → 4. kart normal genişlikte
        let frames = GridLayoutMath.frames(
            layout: layout(.auto),
            container: CGSize(width: 1236, height: 800),
            visibleCount: 4
        )
        XCTAssertEqual(frames[3].width, frames[0].width)
    }

    func testEmptyAndZeroWidthProduceNoFrames() {
        XCTAssertTrue(GridLayoutMath.frames(
            layout: layout(.auto), container: CGSize(width: 1000, height: 800), visibleCount: 0
        ).isEmpty)
        XCTAssertTrue(GridLayoutMath.frames(
            layout: layout(.auto), container: CGSize(width: 0, height: 800), visibleCount: 3
        ).isEmpty)
    }
}
