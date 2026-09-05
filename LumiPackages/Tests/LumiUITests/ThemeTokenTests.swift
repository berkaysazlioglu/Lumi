import CoreGraphics
import XCTest
@testable import LumiUI

/// `Theme.Typography` / `Radius` / `Spacing` / `Motion` ölçeklerinin
/// sözleşmesi (Faz 7.1, design/03 §5).
final class ThemeTokenTests: XCTestCase {
    // MARK: - Tipografi

    func testTypographyScaleIsStrictlyAscending() {
        let points = Theme.Typography.Size.scale.map(\.points)
        XCTAssertEqual(points, points.sorted())
        XCTAssertEqual(Set(points).count, points.count, "ölçekte tekrar eden punto yok")
    }

    func testTypographyScaleContainsThirteenPointBase() {
        // design/03 §5: "13px taban" — ölçek tabanı bağlayıcı.
        XCTAssertEqual(Theme.Typography.Size.base.points, 13)
    }

    func testTypographyScaleHasTwelveSteps() {
        // Faz 7.1 öncesi 17 farklı literal punto vardı; ölçek 11 basamağa indi.
        // İkinci dalgada `heading` (20) eklendi: markdown başlık merdiveni
        // 18→22 boşluğunda çöküyordu (H1 = H2).
        XCTAssertEqual(Theme.Typography.Size.scale.count, 12)
    }

    func testTypographyScaleUsesWholePoints() {
        // 10.5 / 11.5 / 12.5 gibi tek kullanımlık ara değerler ölçeğe girmez.
        for size in Theme.Typography.Size.scale {
            XCTAssertEqual(size.points, size.points.rounded(.down), "\(size.points) tam sayı değil")
        }
    }

    func testTypographySizeIsComparable() {
        XCTAssertLessThan(Theme.Typography.Size.label, Theme.Typography.Size.body)
        XCTAssertLessThan(Theme.Typography.Size.body, Theme.Typography.Size.base)
    }

    // MARK: - Yarıçap

    func testRadiusScaleIsAscendingAndSmall() {
        XCTAssertEqual(Theme.Radius.scale, Theme.Radius.scale.sorted())
        XCTAssertEqual(Theme.Radius.scale, [4, 6, 8, 16])
    }

    // MARK: - Boşluk

    func testSpacingScaleIsAscending() {
        XCTAssertEqual(Theme.Spacing.scale, Theme.Spacing.scale.sorted())
        XCTAssertEqual(Theme.Spacing.scale, [1, 2, 4, 6, 8, 12, 16, 24, 32])
    }

    // MARK: - Motion

    func testMotionDurationsStayInDesignBand() {
        // design/03 §5: fade/slide/height-collapse 0.1–0.3s bandında.
        for duration in [Theme.Motion.quick, Theme.Motion.standard, Theme.Motion.panel] {
            XCTAssertGreaterThanOrEqual(duration, 0.1)
            XCTAssertLessThanOrEqual(duration, 0.3)
        }
    }

    func testMotionDurationsAreOrdered() {
        XCTAssertLessThan(Theme.Motion.quick, Theme.Motion.standard)
        XCTAssertLessThan(Theme.Motion.standard, Theme.Motion.panel)
    }

    func testHoverDelaysArePositive() {
        XCTAssertGreaterThan(Theme.Motion.hoverRevealDelay, .zero)
        XCTAssertGreaterThan(Theme.Motion.hoverOpenDelay, .zero)
        XCTAssertGreaterThan(Theme.Motion.hoverCloseDelay, .zero)
        // Kapanış payı açılış gecikmesinden kısa olmalı: buton ↔ popover
        // geçişinde dropdown kapanmadan yeniden açılabilsin.
        XCTAssertLessThan(Theme.Motion.hoverCloseDelay, Theme.Motion.hoverOpenDelay)
    }
}
