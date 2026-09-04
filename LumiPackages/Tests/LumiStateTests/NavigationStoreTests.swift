import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// `NavigationStore` birim testleri — facade'sız (refactor 5.2).
/// Facade davranışı `WorkspaceStoreTests`'te ayrıca kilitlidir.
@MainActor
final class NavigationStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var terminals: SpyTerminalFocusCoordinator!
    private var store: NavigationStore!

    override func setUp() async throws {
        config = FakeConfigService()
        terminals = SpyTerminalFocusCoordinator()
        store = NavigationStore(config: config, terminals: terminals)
    }

    private func waitForPersist(minimumCount: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await config.uiStateUpdateCount < minimumCount {
            if Date() > deadline { return XCTFail("persist gerçekleşmedi") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Route sum type (5.1)

    func testDefaultRouteIsNone() {
        XCTAssertEqual(store.activeRoute, .none)
        XCTAssertNil(store.activeRepoPath)
    }

    func testOpenTabProducesRepoRoute() {
        store.openTab("/r/alpha")
        XCTAssertEqual(store.activeRoute, .repo("/r/alpha"))
        XCTAssertEqual(store.activeRepoPath, "/r/alpha")
    }

    func testContentRouteHasNoRepoProjection() {
        store.openTab("/r/alpha")
        var changes: [String?] = []
        store.onActiveRepoChanged = { _, new in changes.append(new) }

        store.setRoute(.content(ContentRouteID("tasks")))

        XCTAssertEqual(store.activeRoute, .content(ContentRouteID("tasks")))
        XCTAssertNil(store.activeRepoPath, "repo-dışı route repo projeksiyonu üretmez")
        XCTAssertEqual(changes, [nil], "repo → repo-dışı geçişi (old, nil) olarak bildirilir")
        XCTAssertEqual(store.openTabs, ["/r/alpha"], "tab listesi route'tan bağımsızdır")
    }

    func testRouteChangeBetweenNonRepoRoutesIsSilent() {
        var callCount = 0
        store.onActiveRepoChanged = { _, _ in callCount += 1 }

        store.setRoute(.content(ContentRouteID("tasks")))
        store.setRoute(.none)

        XCTAssertEqual(callCount, 0, "repo ekseninde değişiklik yoksa köprü konuşmaz")
    }

    func testOnlyRepoRoutesActivateTerminalSurface() {
        store.setRoute(.content(ContentRouteID("tasks")))
        XCTAssertTrue(terminals.calls.isEmpty, "repo-dışı route terminal yüzeyini etkilemez")

        store.setRoute(.repo("/r/alpha"))
        XCTAssertEqual(terminals.calls, [.activateRepo("/r/alpha")])
    }

    // MARK: - Persist (karar 9)

    func testRepoRoutePersistsAsActiveTabPath() async throws {
        store.openTab("/r/alpha")
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertEqual(persisted.activeTab, "/r/alpha")
        XCTAssertEqual(persisted.openTabs, ["/r/alpha"])
    }

    func testNonRepoRouteWritesNilActiveTab() async throws {
        store.openTab("/r/alpha")
        try await waitForPersist()
        store.setRoute(.content(ContentRouteID("tasks")))
        try await waitForPersist(minimumCount: 2)
        let persisted = await config.uiState()
        XCTAssertNil(persisted.activeTab, "repo-dışı route activeTab'a path yazmaz")
        XCTAssertEqual(persisted.openTabs, ["/r/alpha"], "açık tab'lar korunur")
    }

    // MARK: - activeRoute (K34, additive)

    func testNonRepoRoutePersistsRouteID() async throws {
        store.setRoute(.content(ContentRouteID("tasks")))
        try await waitForPersist()

        let persisted = await config.uiState()
        XCTAssertEqual(persisted.activeRoute, "tasks")
        XCTAssertNil(persisted.activeTab, "iki alan asla aynı anda dolu olmaz")
    }

    func testRepoRouteClearsRouteID() async throws {
        store.setRoute(.content(ContentRouteID("tasks")))
        try await waitForPersist()
        store.openTab("/r/alpha")
        try await waitForPersist(minimumCount: 2)

        let persisted = await config.uiState()
        XCTAssertNil(persisted.activeRoute, "repo tab'ına dönünce bayat route silinir")
        XCTAssertEqual(persisted.activeTab, "/r/alpha")
    }

    func testLoadRestoresContentRoute() {
        let state = UIState(
            openTabs: ["/r/alpha"],
            activeTab: "/r/alpha",
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil,
            activeRoute: "tasks"
        )

        store.load(state: state, repos: [Repo(name: "alpha", path: "/r/alpha", isGitRepo: true, source: .projectsRoot)])

        XCTAssertEqual(store.activeRoute, .content(ContentRouteID("tasks")))
        XCTAssertNil(store.activeRepoPath)
        XCTAssertEqual(store.openTabs, ["/r/alpha"], "tab listesi route'tan bağımsız yüklenir")
    }

    /// `activeRoute` yoksa (eski dosya) `activeTab` otoritedir — karar 9.
    func testLoadFallsBackToActiveTabWhenRouteIsAbsent() {
        let state = UIState(
            openTabs: ["/r/alpha"],
            activeTab: "/r/alpha",
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil
        )

        store.load(state: state, repos: [Repo(name: "alpha", path: "/r/alpha", isGitRepo: true, source: .projectsRoot)])

        XCTAssertEqual(store.activeRoute, .repo("/r/alpha"))
    }

    func testNavigationPersistDoesNotTouchLayoutFields() async throws {
        await config.seed(WorkspaceFixtures.uiState(
            leftSidebarOpen: false,
            rightSidebarOpen: true,
            projectGridLayouts: ["/r/alpha": GridLayout(mode: .columns, count: 3)]
        ))
        store.openTab("/r/alpha")
        try await waitForPersist()

        let persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen, "navigasyon yazımı layout alanlarını ezmez")
        XCTAssertTrue(persisted.rightSidebarOpen)
        XCTAssertEqual(persisted.projectGridLayouts["/r/alpha"], GridLayout(mode: .columns, count: 3))
    }

    // MARK: - Close tab

    func testRequestCloseTabReturnsMinimizedCountWithoutClosing() {
        store.openTab("/r/alpha")
        terminals.minimizedByRepo["/r/alpha"] = [WorkspaceFixtures.meta("t1", repo: "/r/alpha")]

        XCTAssertEqual(store.requestCloseTab("/r/alpha"), 1, "guard sayıyı çağırana döner")
        XCTAssertEqual(store.openTabs, ["/r/alpha"], "tab henüz kapanmaz")
    }

    func testRequestCloseTabWithoutMinimizedClosesImmediately() {
        store.openTab("/r/alpha")
        XCTAssertNil(store.requestCloseTab("/r/alpha"))
        XCTAssertTrue(store.openTabs.isEmpty)
    }

    func testCloseTabEmitsTabClosedEventAfterRepoChange() {
        store.openTab("/r/alpha")
        var order: [String] = []
        store.onActiveRepoChanged = { _, _ in order.append("repoChanged") }
        store.onTabClosed = { order.append("tabClosed(\($0))") }

        store.closeTab("/r/alpha")

        XCTAssertEqual(order, ["repoChanged", "tabClosed(/r/alpha)"])
    }

    func testCloseInactiveTabStillEmitsEviction() {
        store.openTab("/r/alpha")
        store.openTab("/r/beta")
        var evicted: [String] = []
        store.onTabClosed = { evicted.append($0) }

        store.closeTab("/r/alpha")

        XCTAssertEqual(evicted, ["/r/alpha"])
        XCTAssertEqual(store.activeRepoPath, "/r/beta")
    }

    func testClosingLastTabClearsFocus() {
        store.openTab("/r/alpha")
        terminals.calls.removeAll()

        store.closeTab("/r/alpha")

        XCTAssertEqual(store.activeRoute, .none)
        XCTAssertEqual(terminals.calls, [.focus(nil), .closeAll("/r/alpha")])
    }
}
