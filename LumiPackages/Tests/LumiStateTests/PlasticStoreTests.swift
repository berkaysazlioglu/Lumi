import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class PlasticStoreTests: XCTestCase {
    private let path = "/tmp/lumi-plastic-store-test"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func changeset(_ id: Int, daysAgo: Double) -> PlasticChangeset {
        PlasticChangeset(
            changesetID: id, branch: "/main", owner: "me",
            date: now.addingTimeInterval(-daysAgo * 86_400), comment: "cs \(id)"
        )
    }

    private func makeStore(_ service: FakePlasticService) -> PlasticStore {
        let now = self.now
        return PlasticStore(service: service, now: { now })
    }

    func testLoadAllFillsWorkspaceStatusAndChangesets() async {
        let service = FakePlasticService()
        let info = PlasticWorkspaceInfo(changesetID: 10, repository: "r", server: "s@cloud", branch: "/main")
        await service.setWorkspaceInfo(info)
        await service.setStatus([PlasticFileChange(path: "a.cs", status: .modified)])
        await service.setChangesets([changeset(10, daysAgo: 1)])
        let store = makeStore(service)

        await store.loadAll(path)

        XCTAssertEqual(store.workspaces[path], info)
        XCTAssertEqual(store.changes[path]?.map(\.path), ["a.cs"])
        XCTAssertEqual(store.changesets[path]?.map(\.changesetID), [10])
        XCTAssertTrue(store.isCLIAvailable)
        XCTAssertFalse(store.isLoading(path))
        let calls = await service.changesetCalls
        XCTAssertEqual(calls.map(\.limit), [PlasticStore.changesetLimit])
    }

    func testMissingCLIProbesOnceAndSkipsCommands() async {
        let service = FakePlasticService()
        await service.setCLIInstalled(false)
        let store = makeStore(service)

        await store.loadAll(path)
        await store.loadAll(path)
        await store.refreshStatus(path)

        XCTAssertFalse(store.isCLIAvailable)
        let probes = await service.cliProbeCount
        XCTAssertEqual(probes, 1)
        let statusCalls = await service.statusCalls
        XCTAssertTrue(statusCalls.isEmpty)
    }

    func testRecentChangesetsUsesSevenDayWindow() {
        let all = [changeset(3, daysAgo: 0.5), changeset(2, daysAgo: 6.9), changeset(1, daysAgo: 7.1)]

        let recent = PlasticStore.select(from: all, now: now)

        XCTAssertEqual(recent.items.map(\.changesetID), [3, 2])
        XCTAssertFalse(recent.isFallback)
    }

    func testRecentChangesetsFallsBackToLatestWhenWindowEmpty() {
        let all = (0 ..< 40).map { changeset(100 - $0, daysAgo: 30 + Double($0)) }

        let recent = PlasticStore.select(from: all, now: now)

        XCTAssertTrue(recent.isFallback)
        XCTAssertEqual(recent.items.count, PlasticStore.fallbackCount)
        XCTAssertEqual(recent.items.first?.changesetID, 100)
    }

    func testRecentChangesetsEmptyInputIsNotFallback() {
        XCTAssertEqual(PlasticStore.select(from: [], now: now), .empty)
    }

    func testRefreshStatusOnlyTouchesStatus() async {
        let service = FakePlasticService()
        await service.setStatus([PlasticFileChange(path: "b.cs", status: .added)])
        let store = makeStore(service)

        await store.refreshStatus(path)

        XCTAssertEqual(store.changes[path]?.map(\.path), ["b.cs"])
        let infoCalls = await service.workspaceInfoCalls
        let changesetCalls = await service.changesetCalls
        XCTAssertTrue(infoCalls.isEmpty)
        XCTAssertTrue(changesetCalls.isEmpty)
    }

    func testEvictDropsEverythingForPath() async {
        let service = FakePlasticService()
        await service.setWorkspaceInfo(PlasticWorkspaceInfo(changesetID: 1, repository: "r", server: "s", branch: nil))
        await service.setChangesets([changeset(1, daysAgo: 0)])
        await service.setStatus([PlasticFileChange(path: "a", status: .modified)])
        let store = makeStore(service)
        await store.loadAll(path)

        store.evict(path)

        XCTAssertNil(store.workspaces[path])
        XCTAssertNil(store.changesets[path])
        XCTAssertNil(store.changes[path])
        XCTAssertEqual(store.recentChangesets(path), .empty)
    }
}
