import LumiKit
import SwiftUI
import XCTest
@testable import LumiUI

/// Seviye → renk eşlemesi (refactor 7.5): eşiklerin kendisi LumiKit'te
/// (`UsageLevelTests`), burada yalnız tema eşlemesi kilitlenir.
@MainActor
final class UsageLevelColorTests: XCTestCase {
    func testLevelsMapToPaletteColors() {
        XCTAssertEqual(UsageLevel.normal.color, Theme.success)
        XCTAssertEqual(UsageLevel.warning.color, Theme.warning)
        XCTAssertEqual(UsageLevel.critical.color, Theme.error)
    }

    func testPercentGoesThroughTheSharedThresholds() {
        XCTAssertEqual(UsageLevel(percent: 49).color, Theme.success)
        XCTAssertEqual(UsageLevel(percent: 50).color, Theme.warning)
        XCTAssertEqual(UsageLevel(percent: 80).color, Theme.error)
    }
}
