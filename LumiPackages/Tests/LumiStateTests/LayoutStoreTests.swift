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
        XCTAssertFalse(store.isSlotVisible(.left), "eski bool'dan türetilen görünürlük (K34)")
        XCTAssertTrue(store.isSlotVisible(.right))
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

    // MARK: - Auto-reveal (karar 44)

    func testSetAutoRevealPersistsAndIsIdempotent() async throws {
        store.setAutoReveal(.right, true)
        XCTAssertTrue(store.isAutoReveal(.right))
        try await waitForPersist()
        let persisted = await config.uiState().panelLayout
        XCTAssertEqual(persisted?.autoRevealSlots, [.right])

        let before = await config.uiStateUpdateCount
        store.setAutoReveal(.right, true)
        try await Task.sleep(for: .milliseconds(30))
        let after = await config.uiStateUpdateCount
        XCTAssertEqual(before, after, "değişmedi → yazım yok")
    }

    func testRevealOnlyWorksForHiddenAutoRevealSlot() {
        // Sol yuva default'ta GÖRÜNÜR → reveal anlamsız
        store.setAutoReveal(.left, true)
        XCTAssertFalse(store.canAutoReveal(.left))
        store.setRevealed(.left, true)
        XCTAssertFalse(store.isSlotRevealed(.left))

        // Gizlenince eligible olur
        store.setSlotVisible(.left, false)
        XCTAssertTrue(store.canAutoReveal(.left))
        store.setRevealed(.left, true)
        XCTAssertTrue(store.isSlotRevealed(.left))
        store.setRevealed(.left, false)
        XCTAssertFalse(store.isSlotRevealed(.left))
    }

    func testRevealWithoutAutoRevealPreferenceIsIgnored() {
        store.setSlotVisible(.left, false)
        store.setRevealed(.left, true)
        XCTAssertFalse(store.isSlotRevealed(.left), "tercih kapalıyken kenar hover'ı açmaz")
    }

    func testDockingOrDisablingClearsReveal() {
        store.setAutoReveal(.right, true)
        store.setRevealed(.right, true)
        XCTAssertTrue(store.isSlotRevealed(.right))

        store.setSlotVisible(.right, true)
        XCTAssertFalse(store.isSlotRevealed(.right), "yuva sabitlendi → overlay düşer")

        store.setSlotVisible(.right, false)
        store.setRevealed(.right, true)
        store.setAutoReveal(.right, false)
        XCTAssertFalse(store.isSlotRevealed(.right), "tercih kapatıldı → overlay düşer")
    }

    func testFocusModeSuppressesReveal() {
        store.setAutoReveal(.right, true)
        store.setRevealed(.right, true)
        store.toggleFocusMode()
        XCTAssertFalse(store.canAutoReveal(.right))
        XCTAssertFalse(store.isSlotRevealed(.right))
        store.exitFocusMode()
        XCTAssertFalse(store.isSlotRevealed(.right), "focus mode'a girince reveal sıfırlanır")
    }

    func testRevealIsSessionOnlyAndNotInSnapshot() {
        store.setAutoReveal(.right, true)
        store.setRevealed(.right, true)
        XCTAssertEqual(
            store.snapshot.panelLayout,
            PanelLayout.defaults.settingAutoReveal(.right, true),
            "revealedSlots persist edilmez"
        )
    }

    // MARK: - Snapshot / persist

    func testSnapshotCarriesOnlyPersistedFields() {
        store.setSlotVisible(.left, false)
        store.setGridLayout(GridLayout(mode: .auto, count: 2), for: "/r/alpha")
        XCTAssertEqual(
            store.snapshot,
            LayoutSnapshot(
                panelLayout: PanelLayout.defaults.settingVisible(.left, false),
                projectGridLayouts: ["/r/alpha": GridLayout(mode: .auto, count: 2)]
            )
        )
        XCTAssertFalse(store.snapshot.leftSidebarOpen, "karar 9 projeksiyonu")
        XCTAssertFalse(store.snapshot.rightSidebarOpen)
    }

    func testPersistsAreSerializedSoLatestSnapshotLands() async throws {
        await config.setFirstUIStateWriteDelay(.milliseconds(50))

        store.setSlotVisible(.left, false)
        store.setSlotVisible(.right, true)

        try await waitForPersist(minimumCount: 2)
        let persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen)
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    func testLayoutPersistDoesNotTouchNavigationFields() async throws {
        await config.seed(WorkspaceFixtures.uiState(openTabs: ["/r/alpha"], activeTab: "/r/alpha"))
        store.toggleSlot(.left)
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

    // MARK: - Panel yerleşimi (Faz 6.2)

    func testDefaultLayoutPlacesSessionsLeftAndGitRight() {
        XCTAssertEqual(store.items(in: .left), [.sessions])
        XCTAssertEqual(store.items(in: .right), [.projectTools])
        XCTAssertEqual(store.width(for: .left), PanelLayout.defaultWidth)
        XCTAssertEqual(store.visibleSlots, [.left], "sağ panel default kapalı")
    }

    /// **Ana hedef:** bir öğeyi soldan sağa taşımak TEK mutasyondur.
    func testMovingItemFromLeftToRightIsASingleMutation() async throws {
        store.move(item: .sessions, to: .right, index: 0)

        XCTAssertEqual(store.items(in: .left), [])
        XCTAssertEqual(store.items(in: .right), [.sessions, .projectTools])
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertEqual(persisted.panelLayout?.items(in: .right).first, .sessions)
    }

    func testMovingWithoutIndexAppends() {
        store.move(item: .sessions, to: .right)
        XCTAssertEqual(store.items(in: .right), [.projectTools, .sessions])
    }

    func testMoveToSamePositionDoesNotPersist() async throws {
        store.move(item: .sessions, to: .left, index: 0)
        try await Task.sleep(for: .milliseconds(50))
        let writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0, "değişmeyen yerleşim yazım doğurmaz")
    }

    func testWidthIsClampedAndPersisted() async throws {
        store.setWidth(10_000, for: .left)
        XCTAssertEqual(store.width(for: .left), PanelLayout.maxWidth)
        store.setWidth(1, for: .left)
        XCTAssertEqual(store.width(for: .left), PanelLayout.minWidth)

        try await waitForPersist(minimumCount: 2)
        let persisted = await config.uiState()
        XCTAssertEqual(persisted.panelLayout?.width(for: .left), PanelLayout.minWidth)
    }

    /// K34 migration: yeni anahtar yoksa görünürlük eski bool'lardan türer,
    /// yerleşim default kalır.
    func testMigratesVisibilityFromLegacySidebarBooleans() {
        store.load(
            state: WorkspaceFixtures.uiState(leftSidebarOpen: false, rightSidebarOpen: true),
            openTabs: []
        )
        XCTAssertEqual(store.visibleSlots, [.right])
        XCTAssertEqual(store.items(in: .left), [.sessions], "yerleşim default'tan gelir")
    }

    /// Yeni anahtar VARSA otoritedir (eski bool'lar yok sayılır).
    func testStoredPanelLayoutWinsOverLegacyBooleans() {
        var state = WorkspaceFixtures.uiState(leftSidebarOpen: true, rightSidebarOpen: false)
        state.panelLayout = PanelLayout.defaults
            .moving(.fileTree, to: .right, index: 0)
            .settingVisible(.left, false)
            .settingVisible(.right, true)
        store.load(state: state, openTabs: [])

        XCTAssertEqual(store.visibleSlots, [.right])
        XCTAssertEqual(store.items(in: .left), [.sessions])
        XCTAssertEqual(store.items(in: .right), [.fileTree, .projectTools])
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
