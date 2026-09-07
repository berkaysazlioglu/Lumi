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
        return PlasticStore(service: service, toasts: ToastStore(autoDismissAfter: 60), now: { now })
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

    func testRecentChangesetsUsesSevenDayWindowOrderedByChangesetID() {
        let all = [changeset(2, daysAgo: 0.5), changeset(3, daysAgo: 6.9), changeset(1, daysAgo: 7.1)]

        let recent = PlasticStore.select(from: all, now: now)

        XCTAssertEqual(recent.items.map(\.changesetID), [3, 2], "sıra tarihe değil id'ye göredir (topolojik)")
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

    // MARK: Seçim + checkin

    func testStatusLoadSelectsAllUntilUserTogglesThenPreservesSelection() async {
        let service = FakePlasticService()
        await service.setStatus([PlasticFileChange(path: "a", status: .modified), PlasticFileChange(path: "b", status: .added)])
        let store = makeStore(service)

        await store.refreshStatus(path)
        XCTAssertEqual(store.selectedFiles[path], ["a", "b"])

        store.toggleFile(path, path: "b")
        await service.setStatus([PlasticFileChange(path: "a", status: .modified), PlasticFileChange(path: "c", status: .untracked)])
        await store.refreshStatus(path)
        XCTAssertEqual(store.selectedFiles[path], ["a"], "kullanıcı dokunduysa yeni dosya kendiliğinden seçilmez")
    }

    func testCanCheckinRequiresSelectionAndMessage() async {
        let service = FakePlasticService()
        await service.setStatus([PlasticFileChange(path: "a", status: .modified)])
        let store = makeStore(service)
        await store.refreshStatus(path)

        XCTAssertFalse(store.canCheckin(path), "mesaj boş")
        store.setCheckinMessage("  ", for: path)
        XCTAssertFalse(store.canCheckin(path))
        store.setCheckinMessage("fix", for: path)
        XCTAssertTrue(store.canCheckin(path))
        store.toggleSelectAll(path)
        XCTAssertFalse(store.canCheckin(path), "seçim boş")
    }

    func testCheckinSendsSortedSelectionClearsMessageAndReloads() async {
        let service = FakePlasticService()
        await service.setStatus([PlasticFileChange(path: "b", status: .modified), PlasticFileChange(path: "a", status: .added)])
        let store = makeStore(service)
        await store.refreshStatus(path)
        store.setCheckinMessage("  lid fix ", for: path)

        await store.checkin(path)

        let calls = await service.checkinCalls
        XCTAssertEqual(calls, [FakePlasticService.CheckinCall(workspacePath: path, message: "lid fix", files: ["a", "b"])])
        XCTAssertEqual(store.checkinMessage(for: path), "")
        XCTAssertEqual(store.changes[path], [], "başarılı checkin sonrası durum yeniden yüklenir")
        XCTAssertFalse(store.isCheckingIn)
    }

    func testCheckinFailureKeepsMessageAndReportsToast() async {
        let service = FakePlasticService()
        await service.setStatus([PlasticFileChange(path: "a", status: .modified)])
        await service.setErrorToThrow(.plasticFailed(operation: "checkin", detail: "no changes"))
        let toasts = ToastStore(autoDismissAfter: 60)
        let now = self.now
        let store = PlasticStore(service: service, toasts: toasts, now: { now })
        await store.refreshStatus(path)
        store.setCheckinMessage("fix", for: path)

        await store.checkin(path)

        XCTAssertEqual(store.checkinMessage(for: path), "fix")
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    func testUndoRefreshesStatusOnly() async {
        let service = FakePlasticService()
        await service.setStatus([PlasticFileChange(path: "a", status: .modified), PlasticFileChange(path: "b", status: .modified)])
        let store = makeStore(service)
        await store.refreshStatus(path)

        await store.undo(path, path: "a")

        let undo = await service.undoCalls
        XCTAssertEqual(undo, [["a"]])
        XCTAssertEqual(store.changes[path]?.map(\.path), ["b"])
        let changesetCalls = await service.changesetCalls
        XCTAssertTrue(changesetCalls.isEmpty)
    }
}
