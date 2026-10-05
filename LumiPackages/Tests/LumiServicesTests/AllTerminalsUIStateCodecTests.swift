import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 103: All Terminals'ın iki additive `ui-state` anahtarı. Round-trip
/// `ConfigCodecIntegrityTests`'tedir; burada varsayılan değerin diske hiç
/// girmediği (karar 9) ve bozuk girdinin okumayı düşürmediği kilitlenir.
final class AllTerminalsUIStateCodecTests: XCTestCase {
    func testDefaultsWriteNoAllTerminalsKeys() {
        let overlay = ConfigCodec.uiStateOverlay(.defaults)
        XCTAssertNil(overlay["allTerminalsGridLayout"])
        XCTAssertNil(overlay["allTerminalsOrder"])
    }

    func testPopulatedValuesAreWritten() {
        var state = UIState.defaults
        state.allTerminalsGridLayout = GridLayout(mode: .columns, count: 2, heightMode: .fit)
        state.allTerminalsOrder = ["s-2", "s-1"]

        let overlay = ConfigCodec.uiStateOverlay(state)

        XCTAssertEqual((overlay["allTerminalsGridLayout"] as? [String: Any])?["count"] as? Int, 2)
        XCTAssertEqual(overlay["allTerminalsOrder"] as? [String], ["s-2", "s-1"])
    }

    func testMalformedValuesFallBackToDefaults() {
        let decoded = UIStateCodec.decode([
            "allTerminalsGridLayout": ["mode": "bogus"],
            "allTerminalsOrder": ["s-1", 42, NSNull(), "s-2"],
        ])
        XCTAssertNil(decoded.allTerminalsGridLayout)
        XCTAssertEqual(decoded.allTerminalsOrder, ["s-1", "s-2"])
    }

    func testMissingKeysDecodeAsDefaults() {
        let decoded = UIStateCodec.decode([:])
        XCTAssertNil(decoded.allTerminalsGridLayout)
        XCTAssertTrue(decoded.allTerminalsOrder.isEmpty)
    }

    // MARK: - Karar 108: recentLooseLocations

    func testRecentLooseLocationsAreWrittenOnlyWhenPopulated() {
        XCTAssertNil(ConfigCodec.uiStateOverlay(.defaults)["recentLooseLocations"])

        var state = UIState.defaults
        state.recentLooseLocations = ["/Users/me", "/src"]
        XCTAssertEqual(ConfigCodec.uiStateOverlay(state)["recentLooseLocations"] as? [String], ["/Users/me", "/src"])
    }

    func testRecentLooseLocationsDropMalformedEntriesAndAreCapped() {
        let decoded = UIStateCodec.decode([
            "recentLooseLocations": ["/a", 1, NSNull(), "/b", "/c", "/d", "/e", "/f"],
        ])
        XCTAssertEqual(decoded.recentLooseLocations, ["/a", "/b", "/c", "/d", "/e"])
        XCTAssertTrue(UIStateCodec.decode([:]).recentLooseLocations.isEmpty)
    }
}
