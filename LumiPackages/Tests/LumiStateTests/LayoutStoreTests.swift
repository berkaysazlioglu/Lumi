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

    // MARK: - Edit modu (karar 97)

    func testArrangingIsScopedToRepoAndToggles() {
        store.toggleArranging(in: "/a")
        XCTAssertTrue(store.isArranging(in: "/a"))
        XCTAssertFalse(store.isArranging(in: "/b"))

        store.toggleArranging(in: "/a")
        XCTAssertFalse(store.isArranging(in: "/a"))
    }

    func testEnteringArrangeLeavesMaximize() {
        let id = TerminalID()
        visible = [id]
        store.maximize(id, in: "/a")

        store.toggleArranging(in: "/a")

        XCTAssertNil(store.maximizedTerminal(in: "/a"))
    }

    func testMaximizeEndsArranging() {
        let id = TerminalID()
        visible = [id]
        store.toggleArranging(in: "/a")

        store.maximize(id, in: "/a")

        XCTAssertFalse(store.isArranging(in: "/a"))
        XCTAssertEqual(store.maximizedTerminal(in: "/a"), id)
    }

    func testEvictEndsArrangingOnlyForThatRepo() {
        store.toggleArranging(in: "/a")
        store.evict("/b")
        XCTAssertTrue(store.isArranging(in: "/a"))
        store.evict("/a")
        XCTAssertNil(store.arrangingScope)
    }

    // MARK: - Arayüz ölçeği (karar 61)

    func testZoomStepsThroughTheClosedSet() {
        XCTAssertEqual(store.uiScale, 1)

        store.zoomIn()
        XCTAssertEqual(store.uiScale, 1.1)
        store.zoomIn()
        XCTAssertEqual(store.uiScale, 1.25)
        store.zoomOut()
        store.zoomOut()
        XCTAssertEqual(store.uiScale, 1)
        store.zoomOut()
        XCTAssertEqual(store.uiScale, 0.9)
    }

    /// Uçlarda sabitlenir — sonsuz büyüme/küçülme yok.
    func testZoomClampsAtBothEnds() {
        for _ in 0..<20 { store.zoomIn() }
        XCTAssertEqual(store.uiScale, LayoutStore.uiScaleSteps.last)
        for _ in 0..<40 { store.zoomOut() }
        XCTAssertEqual(store.uiScale, LayoutStore.uiScaleSteps.first)
    }

    func testResetZoomReturnsToActualSize() {
        store.zoomIn()
        store.zoomIn()
        store.resetZoom()
        XCTAssertEqual(store.uiScale, 1)
    }

    /// Köprü HER değişimde ateşlenir (token çarpanı + arayüzün yeniden kurulması
    /// buna bağlı), ama aynı değere ikinci kez geçişte ateşlenmez.
    func testScaleChangeNotifiesBridgeOnlyOnRealChange() {
        var received: [CGFloat] = []
        store.onUIScaleChanged = { received.append($0) }

        store.zoomIn()
        store.resetZoom()
        store.resetZoom() // zaten %100 — köprü tetiklenmez

        XCTAssertEqual(received, [1.1, 1])
    }

    /// Karar 9: %100 varsayılanında additive anahtar diske YAZILMAZ.
    func testScalePersistsOnlyWhenNotActualSize() async throws {
        store.zoomIn()
        try await waitForPersist()
        var written = await config.uiState()
        XCTAssertEqual(written.uiScale, 1.1)

        store.resetZoom()
        try await waitForPersist(minimumCount: 2)
        written = await config.uiState()
        XCTAssertNil(written.uiScale, "%100'de anahtar yazılmamalı")
    }

    /// Diskteki bozuk/ara değer en yakın basamağa çekilir — arayüz okunamaz
    /// bir ölçekle açılmaz.
    func testLoadSnapsStoredScaleToNearestStep() {
        var state = WorkspaceFixtures.uiState()
        state.uiScale = 1.19
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.uiScale, 1.25)

        state.uiScale = -3
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.uiScale, 1)

        state.uiScale = 99
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.uiScale, LayoutStore.uiScaleSteps.last)
    }

    // MARK: - Arayüz yazı tipi (karar 63)

    /// Anahtar yoksa eski davranış (SF Mono) sürer — mevcut kurulumlar yüz
    /// değiştirmez.
    func testFontFamilyDefaultsToSystemWhenKeyIsAbsent() {
        var state = WorkspaceFixtures.uiState()
        state.uiFontFamily = nil
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.uiFontFamily, .system)
    }

    func testFontFamilyLoadsFromState() {
        var state = WorkspaceFixtures.uiState()
        state.uiFontFamily = .jetBrainsMono
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.uiFontFamily, .jetBrainsMono)
    }

    /// Ölçekteki köprüyle aynı sözleşme: gerçek değişimde ateşlenir, aynı değere
    /// ikinci kez geçişte ateşlenmez (arayüz gereksiz yere yeniden kurulmaz).
    func testFontFamilyChangeNotifiesBridgeOnlyOnRealChange() {
        var received: [UIFontFamily] = []
        store.onUIFontFamilyChanged = { received.append($0) }

        store.setUIFontFamily(.jetBrainsMono)
        store.setUIFontFamily(.jetBrainsMono)
        store.setUIFontFamily(.system)

        XCTAssertEqual(received, [.jetBrainsMono, .system])
    }

    /// Karar 9: varsayılan yüzde additive anahtar diske YAZILMAZ.
    func testFontFamilyPersistsOnlyWhenNotSystem() async throws {
        store.setUIFontFamily(.jetBrainsMono)
        try await waitForPersist()
        var written = await config.uiState()
        XCTAssertEqual(written.uiFontFamily, .jetBrainsMono)

        store.setUIFontFamily(.system)
        try await waitForPersist(minimumCount: 2)
        written = await config.uiState()
        XCTAssertNil(written.uiFontFamily, "varsayılan yüzde anahtar yazılmamalı")
    }

    // MARK: - Sağ panel sekmesi (karar 72)

    /// Seçim view'ın `@State`'indeyken panel her kapanışta Explorer'a
    /// dönüyordu; artık yerleşim durumudur ve yeniden yüklenince korunur.
    func testProjectToolsTabLoadsAndDefaultsToExplorer() {
        var state = WorkspaceFixtures.uiState()
        state.projectToolsTab = nil
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.projectToolsTab, .explorer)

        state.projectToolsTab = "sourceControl"
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.projectToolsTab, .sourceControl)

        // Bilinmeyen değer varsayılana iner (karar 9: okuma asla düşmez).
        state.projectToolsTab = "yokBoyleSekme"
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.projectToolsTab, .explorer)
    }

    /// Karar 9: varsayılan sekmede additive anahtar diske YAZILMAZ.
    func testProjectToolsTabPersistsOnlyWhenNotExplorer() async throws {
        store.setProjectToolsTab(.agentHistory)
        try await waitForPersist()
        var written = await config.uiState()
        XCTAssertEqual(written.projectToolsTab, "agentHistory")

        store.setProjectToolsTab(.explorer)
        try await waitForPersist(minimumCount: 2)
        written = await config.uiState()
        XCTAssertNil(written.projectToolsTab, "varsayılan sekmede anahtar yazılmamalı")
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

    func testDefaultLayoutPlacesTasksLeftAndGitRight() {
        XCTAssertEqual(store.items(in: .left), [.tasks, .projects])
        XCTAssertEqual(store.items(in: .right), [.projectTools])
        XCTAssertEqual(store.width(for: .left), PanelLayout.defaultWidth)
        XCTAssertEqual(store.visibleSlots, [.left], "sağ panel default kapalı")
    }

    /// **Ana hedef:** bir öğeyi soldan sağa taşımak TEK mutasyondur.
    func testMovingItemFromLeftToRightIsASingleMutation() async throws {
        store.move(item: .tasks, to: .right, index: 0)

        XCTAssertEqual(store.items(in: .left), [.projects])
        XCTAssertEqual(store.items(in: .right), [.tasks, .projectTools])
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertEqual(persisted.panelLayout?.items(in: .right).first, .tasks)
    }

    func testMovingWithoutIndexAppends() {
        store.move(item: .tasks, to: .right)
        XCTAssertEqual(store.items(in: .right), [.projectTools, .tasks])
    }

    func testMoveToSamePositionDoesNotPersist() async throws {
        store.move(item: .tasks, to: .left, index: 0)
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
        XCTAssertEqual(store.items(in: .left), [.tasks, .projects], "yerleşim default'tan gelir")
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
        XCTAssertEqual(store.items(in: .left), [.tasks, .projects])
        XCTAssertEqual(store.items(in: .right), [.fileTree, .projectTools])
    }

    // MARK: - Eviction (5.5)

    func testProjectsMigrationPreservesHiddenSidebarAndCustomLayout() async throws {
        var state = UIState.defaults
        state.panelLayout = PanelLayout(
            slots: [.left: [.tasks], .right: [.projectTools]],
            visibleSlots: [.right], widths: [.left: 310], autoRevealSlots: [.left]
        )
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.items(in: .left), [.tasks, .projects])
        XCTAssertEqual(store.visibleSlots, [.right])
        XCTAssertEqual(store.width(for: .left), 310)
        XCTAssertTrue(store.panelLayout.isAutoReveal(.left))
        try await waitForPersist()
        let saved = await config.uiState()
        XCTAssertEqual(saved.panelLayout?.items(in: .left), [.tasks, .projects])
    }

    func testProjectsMigrationReordersLegacyDefaultWithoutChangingMetadata() async throws {
        var state = UIState.defaults
        state.panelLayout = PanelLayout(
            slots: [.left: [.projects, .tasks], .right: [.projectTools]],
            visibleSlots: [.right],
            widths: [.left: 315, .right: 405],
            autoRevealSlots: [.left]
        )

        store.load(state: state, openTabs: [])

        XCTAssertEqual(store.items(in: .left), [.tasks, .projects])
        XCTAssertEqual(store.visibleSlots, [.right])
        XCTAssertEqual(store.width(for: .left), 315)
        XCTAssertEqual(store.width(for: .right), 405)
        XCTAssertTrue(store.panelLayout.isAutoReveal(.left))
        try await waitForPersist()
        let saved = await config.uiState()
        XCTAssertEqual(saved.panelLayout?.items(in: .left), [.tasks, .projects])
    }

    /// Karar 55: diskteki `sessions` öğesi Tasks'a dönüşür ve yeni hâl persist
    /// edilir (bir sonraki açılışta migration tekrar koşmaz).
    func testSessionsItemMigratesToTasksAndPersists() async throws {
        var state = UIState.defaults
        state.panelLayout = PanelLayout(
            slots: [.left: [PanelItemID("sessions"), .projects], .right: [.projectTools]],
            visibleSlots: [.left], widths: [.left: 310]
        )

        store.load(state: state, openTabs: [])

        XCTAssertEqual(store.items(in: .left), [.tasks, .projects])
        XCTAssertEqual(store.width(for: .left), 310)
        try await waitForPersist()
        let saved = await config.uiState()
        XCTAssertEqual(saved.panelLayout?.items(in: .left), [.tasks, .projects])
    }

    func testProjectsMigrationRespectsAnExistingUserMove() {
        var state = UIState.defaults
        state.panelLayout = PanelLayout.defaults.moving(.projects, to: .right, index: 1)
        store.load(state: state, openTabs: [])
        XCTAssertEqual(store.items(in: .left), [.tasks])
        XCTAssertEqual(store.items(in: .right), [.projectTools, .projects])
    }

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
