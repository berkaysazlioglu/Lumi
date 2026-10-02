import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 103: All Terminals yüzeyi — repo görünümünün davranışı tüm
/// projelerin terminalleri üzerinde, proje görünümlerinin durumuna dokunmadan.
@MainActor
final class AllTerminalsScopeTests: XCTestCase {
    private var config: FakeConfigService!
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var viewProvider: FakeTerminalViewProvider!
    private var navigation: NavigationStore!
    private var layout: LayoutStore!

    private let allRoute = WorkspaceRoute.content(.allTerminals)
    private let tasks = WorkspaceRoute.content(ContentRouteID("tasks"))

    override func setUp() async throws {
        config = FakeConfigService()
        service = FakeTerminalService()
        let shared = SharedStores.make(config: config, terminal: service, toastAutoDismissAfter: 60)
        terminals = shared.terminals
        layout = shared.layout
        viewProvider = FakeTerminalViewProvider()
        navigation = NavigationStore(config: config, terminals: terminals, viewProvider: viewProvider)
    }

    @discardableResult
    private func spawn(_ name: String, repo: String = "/r/alpha", claude: String? = nil) -> TerminalMeta {
        let meta = TerminalMeta(
            id: TerminalID(), name: name, repoPath: repo, createdAt: Date(),
            claudeSessionID: claude, provider: claude == nil ? nil : .claude
        )
        terminals.apply(.spawned(meta))
        return meta
    }

    private func names(_ metas: [TerminalMeta]) -> [String] {
        metas.map(\.name)
    }

    /// Kapsam genelindeki yüzey geçişleri — `.all` servise `repoPath: nil`
    /// olarak iner (tekil kart çağrılarında `id` doludur).
    private var scopeSurfaceCalls: [FakeTerminalService.SurfaceStateCall] {
        service.surfaceStateCalls.filter { $0.id == nil }
    }

    // MARK: - Route projeksiyonu

    func testOnlyRepoAndAllTerminalsRoutesAreTerminalSurfaces() {
        XCTAssertEqual(WorkspaceRoute.repo("/r/alpha").terminalScope, .repo("/r/alpha"))
        XCTAssertEqual(allRoute.terminalScope, .all)
        XCTAssertNil(tasks.terminalScope)
        XCTAssertNil(WorkspaceRoute.none.terminalScope)
        XCTAssertNil(allRoute.repoPath, "All Terminals bir repo route'u değildir")
    }

    func testScopeContainment() {
        XCTAssertTrue(TerminalScope.all.contains(repoPath: "/r/any"))
        XCTAssertTrue(TerminalScope.repo("/r/alpha").contains(repoPath: "/r/alpha"))
        XCTAssertFalse(TerminalScope.repo("/r/alpha").contains(repoPath: "/r/beta"))
    }

    // MARK: - Seçiciler

    func testAllScopeListsEveryProjectAndRepoScopeStaysFiltered() {
        spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        spawn("a2")
        terminals.minimize(b1.id)

        XCTAssertEqual(names(terminals.terminals(in: .all)), ["a1", "b1", "a2"])
        XCTAssertEqual(names(terminals.visibleTerminals(in: .all)), ["a1", "a2"])
        XCTAssertEqual(names(terminals.minimizedTerminals(in: .all)), ["b1"])
        XCTAssertEqual(names(terminals.visibleTerminals(in: .repo("/r/alpha"))), ["a1", "a2"])
    }

    // MARK: - Takas

    func testAllScopeSwapLeavesProjectOrderUntouched() {
        let a1 = spawn("a1")
        let a2 = spawn("a2")
        let b1 = spawn("b1", repo: "/r/beta")
        var orderChanges = 0
        terminals.onOrderChanged = { orderChanges += 1 }

        terminals.swap(b1.id, a1.id, in: .all)

        XCTAssertEqual(names(terminals.terminals(in: .all)), ["b1", "a2", "a1"])
        XCTAssertEqual(names(terminals.terminals), ["a1", "a2", "b1"], "proje sırası değişmez")
        XCTAssertEqual(orderChanges, 1)
        _ = a2
    }

    func testRepoScopeSwapRefusesOtherRepos() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        terminals.swap(a1.id, b1.id, in: .repo("/r/alpha"))
        XCTAssertEqual(names(terminals.terminals), ["a1", "b1"])
    }

    func testRepoScopeSwapDoesNotReorderAllTerminals() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        terminals.swap(b1.id, a1.id, in: .all)
        let a2 = spawn("a2")

        terminals.swap(a1.id, a2.id, in: .repo("/r/alpha"))

        XCTAssertEqual(names(terminals.terminals(in: .repo("/r/alpha"))), ["a2", "a1"])
        XCTAssertEqual(names(terminals.terminals(in: .all)), ["b1", "a1", "a2"])
    }

    func testRestoreArrangementPlacesResumedSessions() {
        terminals.restoreAllArrangement(["s-2", "s-1"])
        spawn("first", claude: "s-1")
        spawn("second", repo: "/r/beta", claude: "s-2")

        XCTAssertEqual(names(terminals.terminals(in: .all)), ["second", "first"])
    }

    // MARK: - Yüzey ve odak

    func testEnteringAllTerminalsForegroundsEverySessionWithoutHidingThePreviousRepo() {
        let a1 = spawn("a1")
        spawn("b1", repo: "/r/beta")
        navigation.openTab("/r/alpha")
        service.resetSurfaceStateCalls()

        navigation.setRoute(allRoute)

        XCTAssertEqual(scopeSurfaceCalls.map(\.state), [.foreground])
        XCTAssertEqual(scopeSurfaceCalls.map(\.repoPath), [nil], "tüm terminaller tek çağrıda")
        XCTAssertEqual(terminals.activeTerminalID, a1.id, "aktif terminal korunur")
        XCTAssertEqual(viewProvider.detachAllCount, 0, "yüzeyden yüzeye geçişte detach yok")
        XCTAssertEqual(viewProvider.refreshCallCount, 0)
    }

    func testLeavingAllTerminalsForARepoBackgroundsTheRestFirst() {
        spawn("a1")
        spawn("b1", repo: "/r/beta")
        navigation.setRoute(allRoute)
        service.resetSurfaceStateCalls()

        navigation.openTab("/r/beta")

        XCTAssertEqual(scopeSurfaceCalls.map(\.state), [.background, .foreground])
        XCTAssertEqual(scopeSurfaceCalls.map(\.repoPath), [nil, "/r/beta"])
    }

    func testLeavingAllTerminalsForANonSurfaceRouteDetachesAndReturnRefreshes() {
        spawn("a1")
        navigation.setRoute(allRoute)

        navigation.setRoute(tasks)
        XCTAssertEqual(viewProvider.detachAllCount, 1)

        navigation.setRoute(allRoute)
        XCTAssertEqual(viewProvider.refreshCallCount, 1)
    }

    func testRestoreInAnotherRepoForegroundsWhileAllTerminalsIsVisible() {
        let b1 = spawn("b1", repo: "/r/beta")
        terminals.minimize(b1.id)
        navigation.setRoute(allRoute)
        service.resetSurfaceStateCalls()

        terminals.restore(b1.id)

        XCTAssertEqual(service.surfaceStateCalls.last?.state, .foreground)
        XCTAssertEqual(service.surfaceStateCalls.last?.id, b1.id)
    }

    func testMinimizingTheActiveCardFocusesItsNeighborAcrossProjects() {
        spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        navigation.setRoute(allRoute)
        terminals.focus(b1.id)
        // b1'in görünür komşusu yalnız başka projede.
        terminals.minimize(b1.id)

        XCTAssertEqual(terminals.meta(for: terminals.activeTerminalID!)?.name, "a1")
    }

    func testClosingTheActiveCardFocusesItsNeighborAcrossProjects() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        navigation.setRoute(allRoute)
        terminals.focus(b1.id)

        terminals.apply(.exited(b1.id, code: 0))

        XCTAssertEqual(terminals.activeTerminalID, a1.id)
        XCTAssertEqual(terminals.lastActiveVisible(in: "/r/alpha"), a1.id)
    }

    func testRepoSurfaceStillKeepsFocusInsideTheRepo() {
        spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        navigation.openTab("/r/beta")
        terminals.focus(b1.id)

        terminals.minimize(b1.id)

        XCTAssertNil(terminals.activeTerminalID, "odak başka repo'ya atlamaz")
    }

    func testKeyboardIndexFollowsAllTerminalsOrder() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        terminals.swap(a1.id, b1.id, in: .all)

        terminals.focusIndex(0, in: .all)
        XCTAssertEqual(terminals.activeTerminalID, b1.id)

        terminals.focusNext(in: .all)
        XCTAssertEqual(terminals.activeTerminalID, a1.id)
    }

    func testLoadRestoresAllTerminalsSurface() {
        spawn("a1")
        let state = UIState(
            openTabs: [], activeTab: nil, leftSidebarOpen: true, rightSidebarOpen: false,
            projectGridLayouts: [:], windowBounds: nil, windowMaximized: nil,
            activeRoute: ContentRouteID.allTerminals.rawValue
        )
        service.resetSurfaceStateCalls()

        navigation.load(state: state, repos: [])

        XCTAssertEqual(navigation.activeRoute, allRoute)
        XCTAssertEqual(scopeSurfaceCalls.map(\.repoPath), [nil])
    }

    // MARK: - Layout

    func testMaximizeIsKeptPerScope() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")

        XCTAssertTrue(layout.maximize(b1.id, in: .all))
        XCTAssertNil(layout.maximizedTerminal(in: "/r/alpha"), "repo görünümü etkilenmez")
        XCTAssertEqual(layout.maximizedTerminal(in: .all), b1.id)
        XCTAssertFalse(layout.maximize(b1.id, in: "/r/alpha"), "başka repo'nun terminali repo'da maximize edilmez")
        _ = a1
    }

    func testArrangingIsKeptPerScope() {
        spawn("a1")
        layout.toggleArranging(in: .all)

        XCTAssertTrue(layout.isArranging(in: .all))
        XCTAssertFalse(layout.isArranging(in: "/r/alpha"))

        layout.evict("/r/alpha")
        XCTAssertTrue(layout.isArranging(in: .all), "repo eviction'ı All Terminals'a dokunmaz")
    }

    func testAllTerminalsGridLayoutIsPersistedSeparately() async throws {
        let custom = GridLayout(mode: .columns, count: 3, heightMode: .fit)

        layout.setGridLayout(custom, for: .all)

        XCTAssertEqual(layout.gridLayout(for: .all), custom)
        XCTAssertEqual(layout.gridLayout(for: .repo("/r/alpha")), LayoutStore.defaultGridLayout)
        let deadline = Date().addingTimeInterval(2)
        while await config.uiState().allTerminalsGridLayout != custom {
            if Date() > deadline { return XCTFail("yerleşim diske inmedi") }
            try await Task.sleep(for: .milliseconds(10))
        }
        let persisted = await config.uiState()
        XCTAssertTrue(persisted.projectGridLayouts.isEmpty, "repo sözlüğüne sahte anahtar girmez")
    }

    func testLayoutLoadRestoresAllTerminalsGridLayout() {
        let custom = GridLayout(mode: .auto, count: 2)
        var state = UIState.defaults
        state.allTerminalsGridLayout = custom

        layout.load(state: state, openTabs: [])

        XCTAssertEqual(layout.gridLayout(for: .all), custom)
    }
}
