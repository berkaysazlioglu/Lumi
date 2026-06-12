import XCTest

@testable import LumiTerminal

final class WheelStepAccumulatorTests: XCTestCase {
    func testKlasikTekerlekBirimAltiDeltaBirikir() {
        // Arrange
        var accumulator = WheelStepAccumulator()

        // Act + Assert: 0.4 + 0.4 birikir, üçüncüde eşik aşılır
        XCTAssertEqual(accumulator.consume(delta: 0.4, unit: 1), 0)
        XCTAssertEqual(accumulator.consume(delta: 0.4, unit: 1), 0)
        XCTAssertEqual(accumulator.consume(delta: 0.4, unit: 1), 1)
    }

    func testPreciseDeltaHucreYuksekligineBolunurKalanKorunur() {
        // Arrange: hücre 17px, tek event'te 40px → 2 adım, 6px kalan
        var accumulator = WheelStepAccumulator()

        // Act
        let steps = accumulator.consume(delta: 40, unit: 17)

        // Assert
        XCTAssertEqual(steps, 2)
        // Kalan 6px: 11px daha gelince 17'yi tamamlayıp 1 adım üretmeli
        XCTAssertEqual(accumulator.consume(delta: 11, unit: 17), 1)
    }

    func testAsagiYonNegatifAdimUretir() {
        var accumulator = WheelStepAccumulator()
        XCTAssertEqual(accumulator.consume(delta: -34, unit: 17), -2)
    }

    func testYonDegisimiBirikimiSifirlar() {
        // Arrange: yukarı 10px birikti (adım yok)
        var accumulator = WheelStepAccumulator()
        XCTAssertEqual(accumulator.consume(delta: 10, unit: 17), 0)

        // Act: yön değişti — eski birikim ters yönde gecikme yaratmamalı
        let steps = accumulator.consume(delta: -17, unit: 17)

        // Assert: tam -1 adım (10 - 17 = -7 değil)
        XCTAssertEqual(steps, -1)
    }

    func testSifirVeyaGecersizBirimGuvenli() {
        var accumulator = WheelStepAccumulator()
        XCTAssertEqual(accumulator.consume(delta: 100, unit: 0), 0)
        XCTAssertEqual(accumulator.consume(delta: 0, unit: 17), 0)
    }

    func testTekEventAdimSayisiSinirlanir() {
        var accumulator = WheelStepAccumulator()
        let steps = accumulator.consume(delta: 100_000, unit: 1)
        XCTAssertEqual(steps, WheelStepAccumulator.maxStepsPerEvent)
    }
}

final class MouseWheelEncoderTests: XCTestCase {
    func testSGRWheelRaporuYukari() {
        let bytes = MouseWheelEncoder.sgrWheelReport(up: true, col: 12, row: 5)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "\u{1b}[<64;12;5M")
    }

    func testSGRWheelRaporuAsagi() {
        let bytes = MouseWheelEncoder.sgrWheelReport(up: false, col: 1, row: 1)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "\u{1b}[<65;1;1M")
    }

    func testGridCellFlippedOlmayanKoordinat() {
        // Arrange: 800x480 view, 80x24 grid → hücre 10x20.
        // AppKit non-flipped: y=470 görsel olarak ÜSTTEN 10px → satır 1.
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 480)

        // Act
        let cell = MouseWheelEncoder.gridCell(
            forViewPoint: CGPoint(x: 15, y: 470),
            bounds: bounds, cols: 80, rows: 24, isFlipped: false
        )

        // Assert: x=15 → kolon 2, üstten 10px → satır 1
        XCTAssertEqual(cell.col, 2)
        XCTAssertEqual(cell.row, 1)
    }

    func testGridCellSinirlarinDisiKiskaclanir() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 480)
        let cell = MouseWheelEncoder.gridCell(
            forViewPoint: CGPoint(x: 9_999, y: -50),
            bounds: bounds, cols: 80, rows: 24, isFlipped: false
        )
        XCTAssertEqual(cell.col, 80)
        XCTAssertEqual(cell.row, 24)
    }

    func testGridCellBosBoundsGuvenli() {
        let cell = MouseWheelEncoder.gridCell(
            forViewPoint: .zero, bounds: .zero, cols: 80, rows: 24, isFlipped: false
        )
        XCTAssertEqual(cell.col, 1)
        XCTAssertEqual(cell.row, 1)
    }
}
