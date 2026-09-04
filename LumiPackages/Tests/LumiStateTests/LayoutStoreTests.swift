import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// `LayoutStore` birim testleri — terminal store'una SOMUT bağ yok, görünürlük
/// enjekte edilen predikattan gelir (refactor 5.2).
@MainActor
final class LayoutStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var visible: Set<TerminalID> = []
    private var store: LayoutStore!

    override func setUp() async throws {
        config = FakeConfigService()
        visible = []
        store = LayoutStore(config: config) { [weak self] id, _ in
            self?.visible.contains(id) ?? false
        }
    }

    private func waitForPersist(minimumCount: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await config.uiStateUpdateCount < minimumCount {
            if Date() > deadline { return XCTFail("persist gerçekleşmedi") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Yükleme / migration

    func testLoadAppliesSidebarsAndLayouts() {
        store.load(
            state: WorkspaceFixtures.uiState(
                leftSidebarOpen: false,
                rightSidebarOpen: true,
                projectGridLayouts: ["/r/alpha": GridLayout(mode: .columns, count: 4)]
            ),
            openTabs: ["/r/alpha"]
        )
        XCTAssertFalse(store.leftSidebarOpen)
        XCTAssertTrue(store.rightSidebarOpen)
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .columns, count: 4))
    }

    func testLegacyGridColumnsFanOutToOpenTabs() {
        store.load(
            state: WorkspaceFixtures.uiState(legacyGridColumns: GridLayout(mode: .columns, count: 3)),
            openTabs: ["/r/alpha", "/r/beta"]
        )
        XCTAssertEqual(store.gridLayout(for: "/r/alpha"), GridLayout(mode: .columns, count: 3))
        XCTAssertEqual(store.gridLayout(for: "/r/beta"), GridLayout(mode: .columns, count: 3))
    }

    func testDefaultGridLayoutIsSingleColumnFit() {
        XCTAssertEqual(
            store.gridLayout(for: "/r/unknown"),
            GridLayout(mode: .columns, count: 1, heightMode: .fit),
            "karar 31"
        )
        XCTAssertEqual(store.gridLayout(for: nil), LayoutStore.defaultGridLayout)
    }

    // MARK: - Snapshot / persist

    func testSnapshotCarriesOnlyPersistedFields() {
        store.setLeftSidebarOpen(false)
        store.setGridLayout(GridLayout(mode: .auto, count: 2), for: "/r/alpha")
        XCTAssertEqual(
            store.snapshot,
            LayoutSnapshot(
                leftSidebarOpen: false,
                rightSidebarOpen: false,
                projectGridLayouts: ["/r/alpha": GridLayout(mode: .auto, count: 2)]
            )
        )
    }

    func testPersistsAreSerializedSoLatestSnapshotLands() async throws {
        await config.setFirstUIStateWriteDelay(.milliseconds(50))

        store.setLeftSidebarOpen(false)
        store.setRightSidebarOpen(true)

        try await waitForPersist(minimumCount: 2)
        let persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen)
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    func testLayoutPersistDoesNotTouchNavigationFields() async throws {
        await config.seed(WorkspaceFixtures.uiState(openTabs: ["/r/alpha"], activeTab: "/r/alpha"))
        store.toggleLeftSidebar()
        try await waitForPersist()

        let persisted = await config.uiState()
        XCTAssertEqual(persisted.openTabs, ["/r/alpha"], "layout yazımı tab alanlarını ezmez")
        XCTAssertEqual(persisted.activeTab, "/r/alpha")
    }

    func testEmptyRepoPathIsGuardedFromGridWrites() async throws {
        store.setGridLayout(GridLayout(mode: .auto, count: 2), for: "")
        try await Task.sleep(for: .milliseconds(50))
        let writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0)
    }

    // MARK: - Focus mode (oturumluk)

    func testFocusModeIsSessionOnlyAndBridged() async throws {
        var events: [Bool] = []
        store.onFocusModeChanged = { events.append($0) }

        store.toggleFocusMode()
        store.exitFocusMode()
        store.exitFocusMode() // zaten kapalı → guard

        XCTAssertEqual(events, [true, false])
        try await Task.sleep(for: .milliseconds(50))
        let writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0, "focus mode persist edilmez")
    }

    // MARK: - Maximize (görünürlük predikatı)

    func testMaximizeRejectsInvisibleTerminal() {
        let id = TerminalID()
        XCTAssertFalse(store.maximize(id, in: "/r/alpha"), "görünmeyen terminal maximize edilmez")
        XCTAssertNil(store.maximizedTerminal(in: "/r/alpha"))
    }

    func testMaximizedTerminalDropsWhenItBecomesInvisible() {
        let id = TerminalID()
        visible = [id]
        XCTAssertTrue(store.maximize(id, in: "/r/alpha"))
        XCTAssertEqual(store.maximizedTerminal(in: "/r/alpha"), id)

        visible = [] // kapandı / minimize oldu
        XCTAssertNil(store.maximizedTerminal(in: "/r/alpha"), "stale kayıt okuma sırasında yok sayılır")
    }

    func testMaximizeIsPerRepo() {
        let a = TerminalID()
        let b = TerminalID()
        visible = [a, b]
        store.maximize(a, in: "/r/alpha")
        XCTAssertEqual(store.maximizedTerminal(in: "/r/alpha"), a)
        XCTAssertNil(store.maximizedTerminal(in: "/r/beta"))
    }

    // MARK: - Eviction (5.5)

    func testEvictDropsMaximizeButKeepsPersistedGridLayout() {
        let id = TerminalID()
        visible = [id]
        store.maximize(id, in: "/r/alpha")
        store.setGridLayout(GridLayout(mode: .columns, count: 4), for: "/r/alpha")

        store.evict("/r/alpha")

        XCTAssertNil(store.maximizedTerminal(in: "/r/alpha"), "oturumluk maximize düşer")
        XCTAssertEqual(
            store.gridLayout(for: "/r/alpha"),
            GridLayout(mode: .columns, count: 4),
            "persist edilen yerleşim KORUNUR (karar 9 / kullanıcı tercihi)"
        )
    }
}
