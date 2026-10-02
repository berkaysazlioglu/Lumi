import XCTest
@testable import LumiKit

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndPrefixedTags() {
        XCTAssertEqual(AppVersion("0.8.0")?.components, [0, 8, 0])
        XCTAssertEqual(AppVersion("v0.8.1")?.components, [0, 8, 1])
        XCTAssertEqual(AppVersion("1.2.3-beta")?.components, [1, 2, 3])
    }

    func testNonNumericVersionsAreRejected() {
        for raw in ["dev", "", "v", "0.8.x", "0..1", "-1.0"] {
            XCTAssertNil(AppVersion(raw), raw)
        }
    }

    func testComparisonIsNumericNotLexicographic() {
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
        XCTAssertLessThan(AppVersion("0.7.6")!, AppVersion("0.8.0")!)
        XCTAssertFalse(AppVersion("0.8.0")! < AppVersion("0.8.0")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("0.8")!, AppVersion("0.8.0")!)
        XCTAssertLessThan(AppVersion("0.8")!, AppVersion("0.8.1")!)
    }
}
