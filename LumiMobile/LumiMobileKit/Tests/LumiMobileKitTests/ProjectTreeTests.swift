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
        XCTAssertEqual(agents[0].activity, .running)
    }

    func testOtherGroupsJoinSessionsAndDropEmptyGroups() {
        let snapshot = ProjectsSnapshot(projects: [], others: [
            OtherGroupNode(path: "/tmp", label: "/tmp", agentIds: ["t1", "missing"]),
            OtherGroupNode(path: "/gone", label: "/gone", agentIds: ["missing"]),
        ], addable: [])
        let sessions = [SessionMeta(id: "t1", repoName: "tmp", status: "waiting-unseen", cols: 80, rows: 24)]

        let groups = assembleOtherGroups(snapshot: snapshot, sessions: sessions, selectedId: nil)

        XCTAssertEqual(groups.map(\.id), ["/tmp"])
        XCTAssertEqual(groups[0].agents.map(\.id), ["t1"])
        XCTAssertTrue(groups[0].agents[0].needsAttention)
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

    func testOwningProjectLocationsAndRootTitle() {
        let root = CheckoutNode(kind: "original", title: "main", branch: nil, scm: "git", path: "/p/game", agentIds: ["a"])
        let ws = CheckoutNode(kind: "workspace", title: "wt", branch: "feat", scm: "git", path: "/p/wt", agentIds: ["b"])
        let game = ProjectNode(name: "game", path: "/p/game", checkouts: [root, ws],
                               appearance: ProjectAppearance(color: .lime, rootTitle: "dev"))
        let snapshot = ProjectsSnapshot(
            projects: [game],
            others: [OtherGroupNode(path: "/Users/me", label: "~", agentIds: ["c"]),
                     OtherGroupNode(path: "/tmp", label: "/tmp", agentIds: ["d"])],
            addable: [],
            looseLocations: [LooseLocation(path: "/Users/me", label: "~"), LooseLocation(path: "/src", label: "/src")])

        XCTAssertEqual(owningProject(of: "b", in: snapshot)?.path, "/p/game", "workspace agent → its project")
        XCTAssertNil(owningProject(of: "c", in: snapshot), "loose terminal has no project")
        XCTAssertEqual(looseStartLocations(snapshot).map(\.path), ["/Users/me", "/src", "/tmp"])
        XCTAssertEqual(checkoutDisplayTitle(root, in: game), "dev")
        XCTAssertEqual(checkoutDisplayTitle(ws, in: game), "wt")
    }
}
