import XCTest
import LumiKit
@testable import LumiServices

final class QuickCommandCodecTests: XCTestCase {
    func testMalformedInvalidAndDuplicateRecordsAreDropped() {
        let valid: [String: Any] = ["id": "a", "projectPath": "/p", "name": "Build", "script": "make", "request": "build it"]
        let relative: [String: Any] = ["id": "b", "projectPath": "p", "name": "Build", "script": "make"]
        let emptyScript: [String: Any] = ["id": "c", "projectPath": "/p", "name": "Build", "script": "  "]
        let malformed: [String: Any] = ["id": 4]
        let decoded = QuickCommandCodec.decodeList([valid, relative, emptyScript, malformed, valid])
        XCTAssertEqual(decoded.map(\.id), ["a"])
        XCTAssertEqual(QuickCommandCodec.decodeList("bad"), [])
        XCTAssertEqual(QuickCommandCodec.decodeList(nil), [], "absent key is additive (karar 9)")
    }

    func testMissingRequestDefaultsToEmpty() {
        let decoded = QuickCommandCodec.decodeList([["id": "a", "projectPath": "/p", "name": "N", "script": "ls"]])
        XCTAssertEqual(decoded.first?.request, "")
    }

    func testOverlayRoundTripsFields() {
        let command = ProjectQuickCommand(id: "x", projectPath: "/p", name: "Open", script: "open \"{path}\"\necho ok", request: "open it")
        XCTAssertEqual(QuickCommandCodec.decodeList(QuickCommandCodec.overlayList([command])), [command])
    }
}
