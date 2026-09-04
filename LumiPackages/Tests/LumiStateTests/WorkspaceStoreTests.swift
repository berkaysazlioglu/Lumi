import Foundation
import XCTest
import LumiKit
@testable import LumiState

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var terminalService: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var store: WorkspaceStore!

    private let repos = [
        Repo(name: "alpha", path: "/r/alpha", isGitRepo: true, source: .projectsRoot),
        Repo(name: "beta", path: "/r/beta", isGitRepo: true, source: .projectsRoot),
    ]

    override func setUp() async throws {
        config = FakeConfigService()
        terminalService = FakeTerminalService()
        terminals = TerminalListStore(
            service: terminalService,
            toasts: ToastStore(autoDismissAfter: 60)
        )
        store = WorkspaceStore(config: config, terminals: terminals)
    }

    private func waitForPersist(minimumCount: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await config.uiStateUpdateCount < minimumCount {
            if Date() > deadline {
                return XCTFail("persist gerçekleşmedi")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Migration (karar 11 tab kimliği)

    func testLoadMigratesTabNamesToPaths() async {
        await config.seed(UIState(
            openTabs: ["alpha", "/r/beta", "ghost"],
            activeTab: "alpha",
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil
        ))
        await store.load(repos: repos)

        XCTAssertEqual(store.openTabs, ["/r/alpha", "/r/beta"], "ad→path migration + ghost düşer")
        XCTAssertEqual(store.activeTab, "/r/alpha")
    }

    func testLoadDeduplicatesMigratedTabs() async {
        // Aynı repo hem ad hem path olarak yazılmış olabilir
        await config.seed(UIState(
            openTabs: ["alpha", "/r/alpha"],
            activeTab: nil,
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil
        ))
        await store.load(repos: repos)
        XCTAssertEqual(store.openTabs, ["/r/alpha"])
    }

    func testLoadMigratesLegacyGridColumns() async {
        await config.seed(UIState(
            openTabs: ["/r/alpha", "/r/beta"],
            activeTab: "/r/alpha",
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil,
            legacyGridColumns: GridLayout(mode: .columns, count: 3)
        ))
        await store.load(repos: repos)

        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .columns, count: 3))
        XCTAssertEqual(store.gridLayout(for: "/r/beta"), GridLayout(mode: .columns, count: 3))
    }

    func testLegacyGridColumnsDoesNotOverrideExistingLayouts() async {
        await config.seed(UIState(
            openTabs: ["/r/alpha"],
            activeTab: nil,
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: ["/r/alpha": GridLayout(mode: .columns, count: 2, heightMode: .fit)],
            windowBounds: nil,
            windowMaximized: nil,
            legacyGridColumns: GridLayout(mode: .columns, count: 3)
        ))
        await store.load(repos: repos)
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .columns, count: 2, heightMode: .fit))
    }

    // MARK: - Tab yönetimi

    func testOpenTabAppendsAndActivates() async throws {
        store.openTab("/r/alpha")
        store.openTab("/r/beta")
        store.openTab("/r/alpha") // mevcut → yalnız aktif yapar

        XCTAssertEqual(store.openTabs, ["/r/alpha", "/r/beta"])
        XCTAssertEqual(store.activeTab, "/r/alpha")
        try await waitForPersist()
    }

    func testCloseActiveTabActivatesLastTab() {
        store.openTab("/r/alpha")
        store.openTab("/r/beta")
        store.setActiveTab("/r/alpha")

        store.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertNil(store.closeTabDialog, "minimize yoksa dialog açılmaz")
        XCTAssertEqual(store.openTabs, ["/r/beta"])
        XCTAssertEqual(store.activeTab, "/r/beta")
    }

    func testCloseTabKillsRepoTerminals() {
        store.openTab("/r/alpha")
        let meta = TerminalMeta(id: TerminalID(), name: "t1", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(meta))

        store.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertEqual(terminalService.killedIDs, [meta.id])
    }

    func testCloseTabGuardedByMinimizedTerminals() {
        store.openTab("/r/alpha")
        let meta = TerminalMeta(id: TerminalID(), name: "t1", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(meta))
        terminals.minimize(meta.id)

        store.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertEqual(store.closeTabDialog?.minimizedCount, 1, "guard dialog açılmalı")
        XCTAssertEqual(store.openTabs, ["/r/alpha"], "tab henüz kapanmamalı")
        XCTAssertTrue(terminalService.killedIDs.isEmpty)

        store.confirmCloseTab()
        XCTAssertNil(store.closeTabDialog)
        XCTAssertTrue(store.openTabs.isEmpty)
        XCTAssertEqual(terminalService.killedIDs, [meta.id])
    }

    func testCancelCloseTabKeepsEverything() {
        store.openTab("/r/alpha")
        let meta = TerminalMeta(id: TerminalID(), name: "t1", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(meta))
        terminals.minimize(meta.id)

        store.requestCloseTab("/r/alpha", repoName: "alpha")
        store.cancelCloseTab()
        XCTAssertNil(store.closeTabDialog)
        XCTAssertEqual(store.openTabs, ["/r/alpha"])
        XCTAssertTrue(terminalService.killedIDs.isEmpty)
    }

    // MARK: - Grid layout

    func testGridLayoutDefaultsAndPersistence() async throws {
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), WorkspaceStore.defaultGridLayout)
        store.setGridLayout(GridLayout(mode: .columns, count: 4, heightMode: .fit), for: "/r/alpha")
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .columns, count: 4, heightMode: .fit))
        store.setGridLayout(GridLayout(mode: .auto, count: 2), for: "") // boş path guard'ı
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertEqual(persisted.projectGridLayouts["/r/alpha"], GridLayout(mode: .columns, count: 4, heightMode: .fit))
    }

    // MARK: - Persist sıralaması (1.17)

    func testConcurrentPersistsWriteLatestSnapshotLast() async throws {
        // İlk yazım yavaş: sırasız Task'larda ikinci yazım öne geçer ve bayat
        // snapshot en son diske inerdi.
        await config.setFirstUIStateWriteDelay(.milliseconds(50))

        store.setLeftSidebarOpen(false)
        store.setRightSidebarOpen(true)

        try await waitForPersist(minimumCount: 2)
        let persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen, "son snapshot her iki değişikliği de taşır")
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    // MARK: - Maximize / solo

    func testMaximizeSetsAndTogglesPerRepo() {
        store.openTab("/r/alpha")
        let a = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/r/alpha", createdAt: Date())
        let b = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(a))
        terminals.apply(.spawned(b))

        store.maximize(a.id, in: "/r/alpha")
        XCTAssertEqual(store.maximizedTerminal(in: "/r/alpha"), a.id)
        // Aynı id tekrar toggle → restore
        store.toggleMaximize(a.id, in: "/r/alpha")
        XCTAssertNil(store.maximizedTerminal(in: "/r/alpha"))
    }

    func testMaximizeIsolatedPerRepo() {
        let a = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/r/alpha", createdAt: Date())
        let b = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/r/beta", createdAt: Date())
        terminals.apply(.spawned(a))
        terminals.apply(.spawned(b))
        store.maximize(a.id, in: "/r/alpha")
        XCTAssertEqual(store.maximizedTerminal(in: "/r/alpha"), a.id)
        XCTAssertNil(store.maximizedTerminal(in: "/r/beta"), "diğer repo etkilenmez")
    }

    func testMaximizeIgnoresClosedTerminal() {
        let a = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(a))
        store.maximize(a.id, in: "/r/alpha")
        terminals.apply(.exited(a.id, code: 0)) // kapandı → görünür değil
        XCTAssertNil(store.maximizedTerminal(in: "/r/alpha"))
    }
}
