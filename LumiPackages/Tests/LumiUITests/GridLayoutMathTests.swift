import Foundation
import XCTest
import LumiKit
@testable import LumiUI

/// İki eksenli grid matematiği testleri (design/03).
final class GridLayoutMathTests: XCTestCase {
    private func layout(
        _ mode: GridLayout.Mode,
        _ count: Int = 2,
        _ height: GridLayout.HeightMode = .scroll,
        _ ratio: GridLayout.HeightRatio = .half
    ) -> GridLayout {
        GridLayout(mode: mode, count: count, heightMode: height, heightRatio: ratio)
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

    func testRowCountIsCeilVisibleOverColumns() {
        XCTAssertEqual(GridLayoutMath.rowCount(visibleCount: 5, columns: 3), 2)
        XCTAssertEqual(GridLayoutMath.rowCount(visibleCount: 6, columns: 3), 2)
        XCTAssertEqual(GridLayoutMath.rowCount(visibleCount: 7, columns: 3), 3)
        XCTAssertEqual(GridLayoutMath.rowCount(visibleCount: 0, columns: 3), 0)
    }

    // MARK: - Son satır stretch

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

    // MARK: - Frame: kolon genişlikleri

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

    // MARK: - Yükseklik politikası

    func testFitDividesViewportNoScroll() {
        // fit, columns 2, görünür 4 → 2 satır; rowHeight = floor((800-12)/2)=394
        let frames = GridLayoutMath.frames(
            layout: layout(.columns, 2, .fit),
            container: CGSize(width: 1000, height: 800),
            visibleCount: 4
        )
        XCTAssertEqual(frames[0].height, 394)
        XCTAssertEqual(frames[2].minY, 406) // 394 + 12
        XCTAssertEqual(GridLayoutMath.contentHeight(frames: frames), 800, accuracy: 0.5,
                       "fit içerik tam viewport'a sığmalı")
    }

    func testFitShrinksWhenManyTerminals() {
        // fit, columns 2, görünür 8 → 4 satır; rowHeight = floor((800-3*12)/4)=191
        let frames = GridLayoutMath.frames(
            layout: layout(.columns, 2, .fit),
            container: CGSize(width: 1000, height: 800),
            visibleCount: 8
        )
        XCTAssertEqual(frames[0].height, 191)
        XCTAssertLessThanOrEqual(GridLayoutMath.contentHeight(frames: frames), 800.5,
                                 "fit modda çok terminalde bile scroll yok")
    }

    func testScrollHeightIsViewportHeightTimesRatioRegardlessOfCount() {
        // Karar 106: scroll'da yükseklik viewport yüksekliğinin oranıdır — kolon
        // genişliğinden ve terminal sayısından bağımsız. Oran aralıklarla birlikte
        // uygulanır: (800 + 12) × r − 12.
        for (ratio, expected) in [(GridLayout.HeightRatio.full, 800.0),
                                  (.half, 394.0),
                                  (.third, floor(812.0 / 3.0 - 12))] {
            for columns in [1, 3] {
                let few = GridLayoutMath.frames(
                    layout: layout(.columns, columns, .scroll, ratio),
                    container: CGSize(width: 1000, height: 800),
                    visibleCount: 1
                )
                XCTAssertEqual(few[0].height, CGFloat(expected),
                               "az terminal, \(columns) kolon, oran \(ratio.displayLabel)")
                let many = GridLayoutMath.frames(
                    layout: layout(.columns, columns, .scroll, ratio),
                    container: CGSize(width: 1000, height: 800),
                    visibleCount: 12
                )
                XCTAssertEqual(many[0].height, CGFloat(expected),
                               "çok terminal, \(columns) kolon, oran \(ratio.displayLabel)")
                XCTAssertGreaterThan(GridLayoutMath.contentHeight(frames: many), 800)
            }
        }
    }

    func testFullRatioMatchesMaximizedHeight() {
        // %100 = maximize edilmiş terminalin kapladığı alan; kolon sayısı
        // yüksekliği küçültmez (eski hata: 3 kolonda ~%40'a iniyordu).
        let container = CGSize(width: 1800, height: 1050)
        for columns in 1...5 {
            let frames = GridLayoutMath.frames(
                layout: layout(.columns, columns, .scroll, .full),
                container: container,
                visibleCount: columns
            )
            XCTAssertEqual(frames[0].height, container.height, "\(columns) kolon")
        }
    }

    func testScrollRatioRowsFitViewportLikeFit() {
        // %50'de tam iki, %33'te tam üç satır viewport'a sığar — aynı satır
        // sayısındaki fit yerleşimiyle birebir.
        let container = CGSize(width: 1000, height: 800)
        for (ratio, rows) in [(GridLayout.HeightRatio.half, 2), (.third, 3)] {
            let scroll = GridLayoutMath.frames(
                layout: layout(.columns, 1, .scroll, ratio), container: container, visibleCount: rows
            )
            let fit = GridLayoutMath.frames(
                layout: layout(.columns, 1, .fit), container: container, visibleCount: rows
            )
            XCTAssertEqual(scroll.map(\.height), fit.map(\.height), "oran \(ratio.displayLabel)")
            XCTAssertLessThanOrEqual(GridLayoutMath.contentHeight(frames: scroll), container.height)
        }
    }

    func testScrollHeightNeverNegativeInUnmeasuredViewport() {
        let frames = GridLayoutMath.frames(
            layout: layout(.columns, 1, .scroll, .third),
            container: CGSize(width: 1000, height: 0),
            visibleCount: 2
        )
        XCTAssertEqual(frames[0].height, 0)
    }

    func testHigherRatioMeansTallerTerminals() {
        // Aynı düzende büyük oran → daha uzun terminal → daha çok scroll
        func height(_ ratio: GridLayout.HeightRatio) -> CGFloat {
            GridLayoutMath.frames(
                layout: layout(.columns, 2, .scroll, ratio),
                container: CGSize(width: 1000, height: 400),
                visibleCount: 6
            )[0].height
        }
        XCTAssertGreaterThan(height(.full), height(.half))
        XCTAssertGreaterThan(height(.half), height(.third))
    }

    // MARK: - Stretch frame

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
