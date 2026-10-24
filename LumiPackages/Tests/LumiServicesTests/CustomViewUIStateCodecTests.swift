import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 135: Custom View'ların iki additive `ui-state` anahtarı. Round-trip
/// `ConfigCodecIntegrityTests`'tedir; burada anahtarın hiç yokken yazılmadığı,
/// bir kez yazıldıktan sonra boş hâlinin de yazıldığı ve bozuk girdinin
/// okumayı düşürmediği kilitlenir.
final class CustomViewUIStateCodecTests: XCTestCase {
    func testDefaultsWriteNoCustomViewKeys() {
        let overlay = ConfigCodec.uiStateOverlay(.defaults)
        XCTAssertNil(overlay["customViews"])
        XCTAssertNil(overlay["customViewGridLayouts"])
    }

    func testEmptyListIsWrittenOnceTheKeyExists() {
        var state = UIState.defaults
        state.customViews = []
        state.customViewGridLayouts = [:]

        let overlay = ConfigCodec.uiStateOverlay(state)

        XCTAssertEqual((overlay["customViews"] as? [Any])?.count, 0, "silinen son view diskte kalmasın")
        XCTAssertEqual((overlay["customViewGridLayouts"] as? [String: Any])?.count, 0)
    }

    func testViewsRoundTrip() {
        var state = UIState.defaults
        state.customViews = [CustomViewState(id: "v-1", name: "Amber Falcon", order: ["s-2", "s-1"])]
        state.customViewGridLayouts = ["v-1": GridLayout(mode: .columns, count: 2, heightMode: .fit)]

        let decoded = UIStateCodec.decode(ConfigCodec.uiStateOverlay(state))

        XCTAssertEqual(decoded.customViews, state.customViews)
        XCTAssertEqual(decoded.customViewGridLayouts, state.customViewGridLayouts)
    }

    func testMalformedEntriesAreDropped() {
        let decoded = UIStateCodec.decode([
            "customViews": [
                ["id": "v-1", "name": "  Review  ", "order": ["s-1", 42, "s-2"]],
                ["id": "v-1", "name": "Duplicate", "order": ["s-3"]],
                ["id": "", "name": "No id", "order": []],
                ["id": "v-2", "name": "   ", "order": []],
                ["id": "v-3", "name": "No order"],
                "garbage",
            ],
            "customViewGridLayouts": ["v-1": ["mode": "bogus"]],
        ])

        XCTAssertEqual(decoded.customViews, [
            CustomViewState(id: "v-1", name: "Review", order: ["s-1", "s-2"]),
            CustomViewState(id: "v-3", name: "No order", order: []),
        ])
        XCTAssertEqual(decoded.customViewGridLayouts, [:])
    }

    func testMissingKeysDecodeAsNil() {
        let decoded = UIStateCodec.decode([:])
        XCTAssertNil(decoded.customViews)
        XCTAssertNil(decoded.customViewGridLayouts)
    }
}
