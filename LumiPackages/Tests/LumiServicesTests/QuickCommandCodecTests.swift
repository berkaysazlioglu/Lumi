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

final class QuickCommandRoleCodecTests: XCTestCase {
    func testRoleIsAdditiveAndOnlyOneStartAppPerProjectSurvives() {
        let legacy: [String: Any] = ["id": "a", "projectPath": "/p", "name": "A", "script": "ls"]
        let start1: [String: Any] = ["id": "s1", "projectPath": "/p", "name": "Start App", "script": "open .", "role": "startApp"]
        let start2: [String: Any] = ["id": "s2", "projectPath": "/p", "name": "Start App", "script": "open ..", "role": "startApp"]
        let otherProject: [String: Any] = ["id": "s3", "projectPath": "/q", "name": "Start App", "script": "x", "role": "startApp"]
        let unknown: [String: Any] = ["id": "u", "projectPath": "/p", "name": "U", "script": "ls", "role": "future"]
        let decoded = QuickCommandCodec.decodeList([legacy, start1, start2, otherProject, unknown])
        XCTAssertEqual(decoded.map(\.id), ["a", "s1", "s3", "u"])
        XCTAssertEqual(decoded.map(\.role), [.action, .startApp, .startApp, .action], "absent/unknown role ⇒ action")
    }

    func testRoleRoundTrips() {
        let command = ProjectQuickCommand(id: "s", projectPath: "/p", name: "Start App", script: "open .", role: .startApp)
        XCTAssertEqual(QuickCommandCodec.decodeList(QuickCommandCodec.overlayList([command])), [command])
    }
}
