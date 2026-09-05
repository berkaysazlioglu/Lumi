import Foundation
import XCTest
@testable import LumiKit

/// Kullanım yüzdesi → uyarı seviyesi eşikleri (refactor 7.5). Eşikler SAF
/// mantıktır: renk eşlemesi LumiUI presenter'ının işi, seviye burada test edilir.
final class UsageLevelTests: XCTestCase {
    func testBelowFiftyIsNormal() {
        XCTAssertEqual(UsageLevel(percent: 0), .normal)
        XCTAssertEqual(UsageLevel(percent: 49), .normal)
    }

    func testFiftyToSeventyNineIsWarning() {
        XCTAssertEqual(UsageLevel(percent: 50), .warning)
        XCTAssertEqual(UsageLevel(percent: 79), .warning)
    }

    func testEightyAndAboveIsCritical() {
        XCTAssertEqual(UsageLevel(percent: 80), .critical)
        XCTAssertEqual(UsageLevel(percent: 100), .critical)
    }

    func testOutOfRangeValuesClampToNearestBand() {
        // %100 üstü (CLI bozuk veri) kritik kalır; negatif değer normal.
        XCTAssertEqual(UsageLevel(percent: 250), .critical)
        XCTAssertEqual(UsageLevel(percent: -1), .normal)
        XCTAssertEqual(UsageLevel(percent: Int.min), .normal)
    }
}
