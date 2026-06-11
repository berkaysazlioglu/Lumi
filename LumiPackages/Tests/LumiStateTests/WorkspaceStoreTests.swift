import Foundation
import XCTest
import LumiKit
@testable import LumiState

actor FakeConfigService: ConfigServicing {
    private var storedUIState = UIState.defaults
    private(set) var uiStateUpdateCount = 0

    func seed(_ state: UIState) {
        storedUIState = state
    }

    func config() -> AppConfig { .defaults }
    func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) throws {}

    func uiState() -> UIState { storedUIState }

    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) {
        var state = storedUIState
        mutate(&state)
        storedUIState = state
        uiStateUpdateCount += 1
    }

    func isFirstRun() -> Bool { false }
    func flushPendingWrites() {}

    func events() -> AsyncStream<ConfigEvent> {
        AsyncStream { $0.finish() }
    }
}

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

    // MARK: - Migration (spec/21 §13 + karar 11 tab kimliği)

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
            projectGridLayouts: ["/r/alpha": GridLayout(mode: .rows, count: 2)],
            windowBounds: nil,
            windowMaximized: nil,
            legacyGridColumns: GridLayout(mode: .columns, count: 3)
        ))
        await store.load(repos: repos)
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .rows, count: 2))
    }

    // MARK: - Tab yönetimi (spec/21 §9)

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

    // MARK: - Grid layout (spec/21 §10)

    func testGridLayoutDefaultsAndPersistence() async throws {
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), WorkspaceStore.defaultGridLayout)
        store.setGridLayout(GridLayout(mode: .rows, count: 4), for: "/r/alpha")
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .rows, count: 4))
        store.setGridLayout(GridLayout(mode: .auto, count: 2), for: "") // boş path guard'ı
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertEqual(persisted.projectGridLayouts["/r/alpha"], GridLayout(mode: .rows, count: 4))
    }
}
