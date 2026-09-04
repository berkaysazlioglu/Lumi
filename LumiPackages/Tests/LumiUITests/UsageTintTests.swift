import Foundation
import SwiftUI
import XCTest
import LumiKit
@testable import LumiUI

/// Kullanım göstergesinin SAF renk/oran kuralları (refactor plan 2.8):
/// yeşil < %50 ≤ sarı < %80 ≤ kırmızı ve progress bar dolgusunun 0…1 clamp'i.
@MainActor
final class UsageTintTests: XCTestCase {
    // MARK: - Eşikler

    func testBelowFiftyIsSuccess() {
        XCTAssertEqual(UsageTint.color(for: 0), Theme.success)
        XCTAssertEqual(UsageTint.color(for: 49), Theme.success)
    }

    func testFiftyIsTheFirstWarningValue() {
        XCTAssertEqual(UsageTint.color(for: 50), Theme.warning)
        XCTAssertEqual(UsageTint.color(for: 79), Theme.warning)
    }

    func testEightyIsTheFirstErrorValue() {
        XCTAssertEqual(UsageTint.color(for: 80), Theme.error)
        XCTAssertEqual(UsageTint.color(for: 100), Theme.error)
    }

    func testAboveHundredStaysError() {
        XCTAssertEqual(UsageTint.color(for: 250), Theme.error)
    }

    /// Negatif yüzde parse hatasından gelebilir; mevcut davranış "yeşil"dir
    /// (`..<50` dalı) — kırmızı alarm üretmez.
    func testNegativePercentFallsInSuccessBranch() {
        XCTAssertEqual(UsageTint.color(for: -1), Theme.success)
        XCTAssertEqual(UsageTint.color(for: Int.min), Theme.success)
    }

    // MARK: - UsageWindowRow.fillFraction clamp'i

    private func row(percent: Int?) -> UsageWindowRow {
        UsageWindowRow(
            title: "5-hour session",
            window: UsageWindow(percentUsed: percent, resetsAt: nil, resetsRaw: "", timezone: nil)
        )
    }

    func testFillFractionIsPercentOverHundred() {
        XCTAssertEqual(row(percent: 0).fillFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(row(percent: 42).fillFraction, 0.42, accuracy: 0.0001)
        XCTAssertEqual(row(percent: 100).fillFraction, 1, accuracy: 0.0001)
    }

    func testFillFractionClampsOutOfRangeValues() {
        XCTAssertEqual(row(percent: 250).fillFraction, 1, accuracy: 0.0001, "üstten clamp")
        XCTAssertEqual(row(percent: -30).fillFraction, 0, accuracy: 0.0001, "alttan clamp")
    }

    func testMissingPercentDrawsEmptyBar() {
        XCTAssertEqual(row(percent: nil).fillFraction, 0, accuracy: 0.0001)
    }
}
