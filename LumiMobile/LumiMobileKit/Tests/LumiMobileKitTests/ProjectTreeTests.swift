import XCTest
@testable import LumiMobileKit

final class ProjectTreeTests: XCTestCase {
    private func snap() -> ProjectsSnapshot {
        ProjectsSnapshot(projects: [
            ProjectNode(name: "p", path: "/p", checkouts: [
                CheckoutNode(kind: "original", title: "main", branch: nil, scm: "git",
                             path: "/p", agentIds: ["t1", "missing", "t2"])
            ])
        ], addable: [])
    }

    func testAssemblyJoinsSessionsInAgentIdOrderAndSkipsMissing() {
        let sessions = [
            SessionMeta(id: "t2", repoName: "p", status: "idle", cols: 80, rows: 24, provider: "codex"),
            SessionMeta(id: "t1", repoName: "p", status: "working", cols: 80, rows: 24, provider: "claude"),
        ]
        let tree = assembleProjectTree(snapshot: snap(), sessions: sessions, selectedId: nil)
        let agents = tree[0].checkouts[0].agents
        XCTAssertEqual(agents.map(\.id), ["t1", "t2"])   // agentIds order; "missing" skipped
        XCTAssertEqual(agents[0].provider, "claude")
        XCTAssertEqual(agents[0].badge, .working)
    }

    func testAttention() {
        XCTAssertTrue(terminalNeedsAttention(status: "waiting-unseen", isSelected: false))
        XCTAssertFalse(terminalNeedsAttention(status: "waiting-unseen", isSelected: true))
        XCTAssertTrue(terminalNeedsAttention(status: "waiting-focused", isSelected: false))
        XCTAssertFalse(terminalNeedsAttention(status: "waiting-focused", isSelected: true))
        XCTAssertFalse(terminalNeedsAttention(status: "waiting-seen", isSelected: false))
        XCTAssertFalse(terminalNeedsAttention(status: "idle", isSelected: false))
    }

    func testRelativeTime() {
        let now = 1_000_000.0 * 1000     // pick a base in ms
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now, now: now), "now")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now - 5 * 60_000, now: now), "5m")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now - 3 * 3_600_000, now: now), "3h")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now - 2 * 24 * 3_600_000, now: now), "2d")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(nil, now: now), "")
    }
}
