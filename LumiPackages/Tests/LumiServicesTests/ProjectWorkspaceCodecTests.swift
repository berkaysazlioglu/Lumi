import XCTest
import LumiKit
@testable import LumiServices

final class ProjectWorkspaceCodecTests: XCTestCase {
    func testMalformedAndDuplicateRecordsAreHandled() {
        let valid: [String: Any] = ["projectPath": "/p", "path": "/w", "name": "W", "branch": "w", "scm": "git"]
        let malformed: [String: Any] = ["projectPath": "/p", "path": 4]
        let decoded = ProjectWorkspaceCodec.decodeList([valid, malformed, valid])
        XCTAssertEqual(decoded.count, 1, "codec preserves valid records, ignores malformed entries, and deduplicates paths")
        XCTAssertEqual(ProjectWorkspaceCodec.decodeList("bad").count, 0)
    }

    func testOverlayRoundTripsFields() {
        let record = ProjectWorkspace(projectPath: "/p", path: "/w", name: "W", branch: "feature/w", scm: .plastic)
        let decoded = ProjectWorkspaceCodec.decodeList(ProjectWorkspaceCodec.overlayList([record]))
        XCTAssertEqual(decoded, [record])
    }
}
