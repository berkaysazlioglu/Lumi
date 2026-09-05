import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 43: Resource Manager store — örnekleme, repo grupları, sıralama, kill.
@MainActor
final class ResourceUsageStoreTests: XCTestCase {
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var sampler: FakeProcessSampler!
    private var store: ResourceUsageStore!

    override func setUp() async throws {
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        sampler = FakeProcessSampler(table: nil)
        store = ResourceUsageStore(
            terminals: terminals, terminalService: service, sampler: sampler,
            appPID: 1, hostMemoryBytes: 1 << 34, now: { Date(timeIntervalSince1970: 42) }
        )
    }

    private func spawn(_ name: String, repo: String, pid: Int32) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: repo, createdAt: .now)
        terminals.apply(.spawned(meta))
        service.processIDs[meta.id] = pid
        return meta
    }

    private let ps = """
    1 0 1.0 1000
    100 1 5.0 5000
    101 100 1.0 1000
    200 1 2.0 2000
    300 1 0.5 500
    """

    func testRefreshBuildsSnapshotPerTerminalSubtree() async {
        let alpha = spawn("alpha", repo: "/r/a", pid: 100)
        let beta = spawn("beta", repo: "/r/b", pid: 200)
        await sampler.setTable(ProcessTable.parse(psOutput: ps))

        await store.refresh()

        XCTAssertEqual(store.snapshot?.terminals[alpha.id]?.residentBytes, 6000 * 1024)
        XCTAssertEqual(store.snapshot?.terminals[beta.id]?.cpuPercent, 2.0)
        XCTAssertEqual(store.terminalMemoryBytes, 8000 * 1024)
        XCTAssertEqual(store.snapshot?.app.helpers.residentBytes, 500 * 1024, "pid 300 uygulama yardımcısı")
        XCTAssertEqual(store.appMemoryHistory.count, 1)
        XCTAssertEqual(store.sessionCount, 2)
    }

    func testFailedSampleKeepsPreviousSnapshot() async {
        _ = spawn("alpha", repo: "/r/a", pid: 100)
        await sampler.setTable(ProcessTable.parse(psOutput: ps))
        await store.refresh()
        let previous = store.snapshot
        await sampler.setTable(nil)
        await store.refresh()
        XCTAssertEqual(store.snapshot, previous)
    }

    func testRepoGroupsSortByNameCPUAndMemory() async {
        _ = spawn("zed", repo: "/r/a", pid: 100)
        _ = spawn("amy", repo: "/r/a", pid: 200)
        _ = spawn("solo", repo: "/r/b", pid: 300)
        await sampler.setTable(ProcessTable.parse(psOutput: ps))
        await store.refresh()

        store.sortOption = .name
        XCTAssertEqual(store.repoGroups.map(\.name), ["a", "b"])
        XCTAssertEqual(store.repoGroups.first?.sessions.map(\.title), ["amy", "zed"])

        store.sortOption = .cpu
        XCTAssertEqual(store.repoGroups.first?.sessions.map(\.title), ["zed", "amy"], "zed alt ağacı 6.0%")

        store.sortOption = .memory
        XCTAssertEqual(store.repoGroups.map(\.name), ["a", "b"])
        XCTAssertEqual(store.repoGroups.first?.metrics.residentBytes, 8000 * 1024)
    }

    func testUnsampledTerminalHasNilMetrics() async {
        _ = spawn("ghost", repo: "/r/a", pid: 999)
        await sampler.setTable(ProcessTable.parse(psOutput: ps))
        await store.refresh()
        XCTAssertNil(store.repoGroups.first?.sessions.first?.metrics)
    }

    func testKillRoutesThroughTerminalStore() {
        let alpha = spawn("alpha", repo: "/r/a", pid: 100)
        _ = spawn("beta", repo: "/r/b", pid: 200)
        store.kill(alpha.id)
        XCTAssertEqual(service.killedIDs, [alpha.id])
        store.killAll()
        XCTAssertEqual(service.killedIDs.count, 3)
    }

    func testToggleRepoCollapses() {
        store.toggleRepo("/r/a")
        XCTAssertTrue(store.collapsedRepos.contains("/r/a"))
        store.toggleRepo("/r/a")
        XCTAssertFalse(store.collapsedRepos.contains("/r/a"))
    }
}
