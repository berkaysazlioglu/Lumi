import XCTest
import LumiKit
@testable import LumiServices

final class FavoriteFileCodecTests: XCTestCase {
    func testMalformedEscapingAndDuplicateRecordsAreDropped() {
        let valid: [String: Any] = ["id": "a", "projectPath": "/p", "relativePath": "Assets/A.cs"]
        let relativeProject: [String: Any] = ["id": "b", "projectPath": "p", "relativePath": "A.cs"]
        let escaping: [String: Any] = ["id": "c", "projectPath": "/p", "relativePath": "../A.cs"]
        let samePathOtherID: [String: Any] = ["id": "d", "projectPath": "/p", "relativePath": "Assets/A.cs"]
        let sameIDOtherPath: [String: Any] = ["id": "a", "projectPath": "/p", "relativePath": "B.cs"]
        let decoded = FavoriteFileCodec.decodeList([valid, relativeProject, escaping, samePathOtherID, sameIDOtherPath, ["id": 1]])
        XCTAssertEqual(decoded, [ProjectFavoriteFile(id: "a", projectPath: "/p", relativePath: "Assets/A.cs")])
        XCTAssertEqual(FavoriteFileCodec.decodeList(nil), [], "absent key is additive (karar 9)")
        XCTAssertEqual(FavoriteFileCodec.decodeList("bad"), [])
    }

    func testRoundTrip() {
        let favorites = [
            ProjectFavoriteFile(id: "a", projectPath: "/p", relativePath: "A.cs"),
            ProjectFavoriteFile(id: "b", projectPath: "/q", relativePath: "dir/B.md"),
        ]
        XCTAssertEqual(FavoriteFileCodec.decodeList(FavoriteFileCodec.overlayList(favorites)), favorites)
    }
}
