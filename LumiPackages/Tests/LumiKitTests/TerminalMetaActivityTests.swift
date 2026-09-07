import XCTest
@testable import LumiKit

final class TerminalMetaActivityTests: XCTestCase {
    func testLastActivityFallsBackToCreationDate() {
        let created = Date(timeIntervalSince1970: 100)
        var meta = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/r", createdAt: created)
        XCTAssertEqual(meta.lastActivityAt, created)
        let changed = Date(timeIntervalSince1970: 500)
        meta.statusChangedAt = changed
        XCTAssertEqual(meta.lastActivityAt, changed)
    }
}
