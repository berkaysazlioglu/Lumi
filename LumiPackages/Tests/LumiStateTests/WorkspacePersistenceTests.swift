import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// Kabuk state'inin UÇTAN UCA davranışı — eski `WorkspaceStoreTests`'in
/// devamı (Faz 6.1'de `WorkspaceStore` facade'ı kaldırıldı, testler gerçek
/// store üçlüsüne taşındı; **assertion'lar aynı**).
///
/// Burada `SharedStores` sürülür: tek `ui-state.json` okumasıyla navigation +
/// layout yüklenmesi, iki store'un birbirinin alanını EZMEDEN persist etmesi ve
/// oturumluk alanların diske inmemesi bir arada doğrulanır.
@MainActor
final class WorkspacePersistenceTests: XCTestCase {
    private var config: FakeConfigService!
    private var terminalService: FakeTerminalService!
    private var shared: SharedStores!

    private var navigation: NavigationStore { shared.navigation }
    private var layout: LayoutStore { shared.layout }
    private var dialogs: DialogRouter { shared.dialogs }
    private var terminals: TerminalListStore { shared.terminals }

    private let repos = WorkspaceFixtures.repos

    override func setUp() async throws {
        config = FakeConfigService()
        terminalService = FakeTerminalService()
        shared = SharedStores.make(
            config: config,
            terminal: terminalService,
            toastAutoDismissAfter: 60
        )
    }

    private func load(_ state: UIState) async {
        await config.seed(state)
        let stored = await config.uiState()
        shared.loadWorkspace(state: stored, repos: repos)
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
        await load(WorkspaceFixtures.uiState(
            openTabs: ["alpha", "/r/beta", "ghost"],
            activeTab: "alpha"
        ))
        XCTAssertEqual(navigation.openTabs, ["/r/alpha", "/r/beta"], "ad→path migration + ghost düşer")
        XCTAssertEqual(navigation.activeRepoPath, "/r/alpha")
    }

    func testLoadDeduplicatesMigratedTabs() async {
        await load(WorkspaceFixtures.uiState(openTabs: ["alpha", "/r/alpha"]))
        XCTAssertEqual(navigation.openTabs, ["/r/alpha"])
    }

    func testLoadMigratesLegacyGridColumns() async {
        await load(WorkspaceFixtures.uiState(
            openTabs: ["/r/alpha", "/r/beta"],
            activeTab: "/r/alpha",
            legacyGridColumns: GridLayout(mode: .columns, count: 3)
        ))
        XCTAssertEqual(layout.gridLayout(for: "/r/alpha"), GridLayout(mode: .columns, count: 3))
        XCTAssertEqual(layout.gridLayout(for: "/r/beta"), GridLayout(mode: .columns, count: 3))
    }

    func testLegacyGridColumnsDoesNotOverrideExistingLayouts() async {
        await load(WorkspaceFixtures.uiState(
            openTabs: ["/r/alpha"],
            projectGridLayouts: ["/r/alpha": GridLayout(mode: .columns, count: 2, heightMode: .fit)],
            legacyGridColumns: GridLayout(mode: .columns, count: 3)
        ))
        XCTAssertEqual(
            layout.gridLayout(for: "/r/alpha"),
            GridLayout(mode: .columns, count: 2, heightMode: .fit)
        )
    }

    // MARK: - Tab yönetimi

    func testOpenTabAppendsAndActivates() async throws {
        navigation.openTab("/r/alpha")
        navigation.openTab("/r/beta")
        navigation.openTab("/r/alpha") // mevcut → yalnız aktif yapar

        XCTAssertEqual(navigation.openTabs, ["/r/alpha", "/r/beta"])
        XCTAssertEqual(navigation.activeRepoPath, "/r/alpha")
        try await waitForPersist()
    }

    func testCloseActiveTabActivatesLastTab() {
        navigation.openTab("/r/alpha")
        navigation.openTab("/r/beta")
        navigation.setRoute(.repo("/r/alpha"))

        XCTAssertNil(navigation.requestCloseTab("/r/alpha"), "minimize yoksa dialog gerekmez")
        XCTAssertEqual(navigation.openTabs, ["/r/beta"])
        XCTAssertEqual(navigation.activeRepoPath, "/r/beta")
    }

    func testCloseTabKillsRepoTerminals() {
        navigation.openTab("/r/alpha")
        let meta = WorkspaceFixtures.meta("t1", repo: "/r/alpha")
        terminals.apply(.spawned(meta))

        navigation.requestCloseTab("/r/alpha")
        XCTAssertEqual(terminalService.killedIDs, [meta.id])
    }

    // MARK: - Grid layout

    func testGridLayoutDefaultsAndPersistence() async throws {
        XCTAssertEqual(layout.gridLayout(for: "/r/alpha"), LayoutStore.defaultGridLayout)
        layout.setGridLayout(GridLayout(mode: .columns, count: 4, heightMode: .fit), for: "/r/alpha")
        XCTAssertEqual(
            layout.gridLayout(for: "/r/alpha"),
            GridLayout(mode: .columns, count: 4, heightMode: .fit)
        )
        layout.setGridLayout(GridLayout(mode: .auto, count: 2), for: "") // boş path guard'ı
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertEqual(
            persisted.projectGridLayouts["/r/alpha"],
            GridLayout(mode: .columns, count: 4, heightMode: .fit)
        )
    }

    // MARK: - Persist sıralaması (1.17)

    func testConcurrentPersistsWriteLatestSnapshotLast() async throws {
        // İlk yazım yavaş: sırasız Task'larda ikinci yazım öne geçer ve bayat
        // snapshot en son diske inerdi.
        await config.setFirstUIStateWriteDelay(.milliseconds(50))

        layout.setSlotVisible(.left, false)
        layout.setSlotVisible(.right, true)

        try await waitForPersist(minimumCount: 2)
        let persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen, "son snapshot her iki değişikliği de taşır")
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    // MARK: - Maximize / solo

    func testMaximizeSetsAndTogglesPerRepo() {
        navigation.openTab("/r/alpha")
        let a = WorkspaceFixtures.meta("a", repo: "/r/alpha")
        let b = WorkspaceFixtures.meta("b", repo: "/r/alpha")
        terminals.apply(.spawned(a))
        terminals.apply(.spawned(b))

        layout.maximize(a.id, in: "/r/alpha")
        XCTAssertEqual(layout.maximizedTerminal(in: "/r/alpha"), a.id)
        XCTAssertEqual(terminals.activeTerminalID, a.id, "maximize odak da verir")
        // Aynı id tekrar toggle → restore
        layout.toggleMaximize(a.id, in: "/r/alpha")
        XCTAssertNil(layout.maximizedTerminal(in: "/r/alpha"))
    }

    func testMaximizeIsolatedPerRepo() {
        let a = WorkspaceFixtures.meta("a", repo: "/r/alpha")
        let b = WorkspaceFixtures.meta("b", repo: "/r/beta")
        terminals.apply(.spawned(a))
        terminals.apply(.spawned(b))
        layout.maximize(a.id, in: "/r/alpha")
        XCTAssertEqual(layout.maximizedTerminal(in: "/r/alpha"), a.id)
        XCTAssertNil(layout.maximizedTerminal(in: "/r/beta"), "diğer repo etkilenmez")
    }

    func testMaximizeIgnoresClosedTerminal() {
        let a = WorkspaceFixtures.meta("a", repo: "/r/alpha")
        terminals.apply(.spawned(a))
        layout.maximize(a.id, in: "/r/alpha")
        terminals.apply(.exited(a.id, code: 0)) // kapandı → görünür değil
        XCTAssertNil(layout.maximizedTerminal(in: "/r/alpha"))
    }

    // MARK: - Panel görünürlüğü → persist (karakterizasyon 2.5)

    func testToggleLeftSlotFlipsAndPersists() async throws {
        XCTAssertTrue(layout.isSlotVisible(.left), "default açık")

        layout.toggleSlot(.left)
        XCTAssertFalse(layout.isSlotVisible(.left))
        try await waitForPersist()
        var persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen, "eski bool projeksiyonu yazılmaya devam eder")

        layout.toggleSlot(.left)
        try await waitForPersist(minimumCount: 2)
        persisted = await config.uiState()
        XCTAssertTrue(persisted.leftSidebarOpen)
    }

    func testToggleRightSlotFlipsAndPersists() async throws {
        XCTAssertFalse(layout.isSlotVisible(.right), "default kapalı")

        layout.toggleSlot(.right)
        XCTAssertTrue(layout.isSlotVisible(.right))
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    func testSlotTogglesAreIndependent() async throws {
        layout.toggleSlot(.right)
        try await waitForPersist()
        XCTAssertTrue(layout.isSlotVisible(.left), "sağ toggle solu etkilemez")
        let persisted = await config.uiState()
        XCTAssertTrue(persisted.leftSidebarOpen)
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    func testSetSlotVisiblePersistsOnlyRealChanges() async throws {
        // Aynı değere set → guard → yazım YOK (idempotent setter)
        layout.setSlotVisible(.left, true)
        layout.setSlotVisible(.right, false)
        try await Task.sleep(for: .milliseconds(50))
        var writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0, "değişmeyen setter persist etmez")

        layout.setSlotVisible(.left, false)
        try await waitForPersist()
        writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 1)

        // Yeni değerin tekrarı da yazmaz
        layout.setSlotVisible(.left, false)
        try await Task.sleep(for: .milliseconds(50))
        writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 1)
    }

    // MARK: - UIState round-trip (load → değiştir → persist → yeniden load)

    func testUIStateRoundTripsThroughConfigService() async throws {
        await load(WorkspaceFixtures.uiState(openTabs: ["/r/alpha"], activeTab: "/r/alpha"))

        navigation.openTab("/r/beta")
        layout.setGridLayout(GridLayout(mode: .columns, count: 3, heightMode: .fit), for: "/r/beta")
        layout.toggleSlot(.left)
        layout.toggleSlot(.right)
        try await waitForPersist(minimumCount: 4)

        // Aynı config üzerinden TAZE store'lar: diskteki hal geri okunmalı
        let reloaded = SharedStores.make(config: config, terminal: terminalService)
        reloaded.loadWorkspace(state: await config.uiState(), repos: repos)

        XCTAssertEqual(reloaded.navigation.openTabs, ["/r/alpha", "/r/beta"])
        XCTAssertEqual(reloaded.navigation.activeRepoPath, "/r/beta")
        XCTAssertFalse(reloaded.layout.isSlotVisible(.left))
        XCTAssertTrue(reloaded.layout.isSlotVisible(.right))
        XCTAssertEqual(
            reloaded.layout.gridLayout(for: "/r/beta"),
            GridLayout(mode: .columns, count: 3, heightMode: .fit)
        )
    }

    /// Oturumluk alanlar (focus mode, maximize, repo selector) persist EDİLMEZ.
    func testSessionOnlyStateIsNotPersisted() async throws {
        navigation.openTab("/r/alpha")
        let a = WorkspaceFixtures.meta("a", repo: "/r/alpha")
        terminals.apply(.spawned(a))
        layout.maximize(a.id, in: "/r/alpha")
        layout.toggleFocusMode()
        dialogs.isRepoSelectorOpen = true
        try await waitForPersist()

        let reloaded = SharedStores.make(config: config, terminal: terminalService)
        reloaded.loadWorkspace(state: await config.uiState(), repos: repos)
        XCTAssertFalse(reloaded.layout.isFocusMode)
        XCTAssertNil(reloaded.layout.maximizedTerminal(in: "/r/alpha"))
        XCTAssertFalse(reloaded.dialogs.isRepoSelectorOpen)
    }

    // MARK: - Focus mode köprüsü

    func testToggleFocusModeNotifiesBridgeBothWays() {
        var events: [Bool] = []
        layout.onFocusModeChanged = { events.append($0) }

        layout.toggleFocusMode()
        XCTAssertTrue(layout.isFocusMode)
        layout.toggleFocusMode()
        XCTAssertFalse(layout.isFocusMode)
        XCTAssertEqual(events, [true, false])
    }

    func testExitFocusModeNotifiesOnlyWhenActive() {
        var events: [Bool] = []
        layout.onFocusModeChanged = { events.append($0) }

        layout.exitFocusMode() // zaten kapalı → guard
        XCTAssertEqual(events, [], "kapalıyken exit köprüyü tetiklemez")

        layout.toggleFocusMode()
        layout.exitFocusMode()
        XCTAssertFalse(layout.isFocusMode)
        XCTAssertEqual(events, [true, false])
    }

    func testFocusModeIsNotPersisted() async throws {
        layout.toggleFocusMode()
        try await Task.sleep(for: .milliseconds(50))
        let writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0, "focus mode oturumluk — disk yazımı yok")
    }

    /// Focus mode `visibleSlots`'un GEÇİCİ override'ıdır: kalıcı değer değişmez.
    func testFocusModeHidesSlotsWithoutChangingPersistedVisibility() {
        layout.setSlotVisible(.right, true)
        layout.toggleFocusMode()

        XCTAssertFalse(layout.isSlotVisible(.left))
        XCTAssertFalse(layout.isSlotVisible(.right))
        XCTAssertEqual(layout.visibleSlots, [.left, .right], "kalıcı görünürlük korunur")

        layout.exitFocusMode()
        XCTAssertTrue(layout.isSlotVisible(.left))
        XCTAssertTrue(layout.isSlotVisible(.right))
    }

    // MARK: - Quit dialog (.terminateLater akışı)

    func testResolveQuitTrueClearsDialogAndReportsDecision() {
        var decisions: [Bool] = []
        dialogs.onQuitResolved = { decisions.append($0) }

        dialogs.presentQuitDialog(terminalCount: 3)
        XCTAssertEqual(dialogs.quitDialogTerminalCount, 3)
        XCTAssertTrue(decisions.isEmpty, "dialog açılırken karar bildirilmez")

        dialogs.resolveQuit(true)
        XCTAssertNil(dialogs.quitDialogTerminalCount)
        XCTAssertEqual(decisions, [true])
    }

    func testResolveQuitFalseAlsoClearsDialog() {
        var decisions: [Bool] = []
        dialogs.onQuitResolved = { decisions.append($0) }

        dialogs.presentQuitDialog(terminalCount: 1)
        dialogs.resolveQuit(false)
        XCTAssertNil(dialogs.quitDialogTerminalCount)
        XCTAssertEqual(decisions, [false])
    }

    func testPresentQuitDialogWithZeroTerminalsStillOpens() {
        // Guard store'da değil çağıranda: 0 da geçerli bir sunum durumudur.
        dialogs.presentQuitDialog(terminalCount: 0)
        XCTAssertEqual(dialogs.quitDialogTerminalCount, 0)
    }

    // MARK: - onActiveRepoChanged (watch/unwatch köprüsü)

    private struct RepoChange: Equatable {
        let old: String?
        let new: String?
    }

    func testLoadAnnouncesInitialActiveRepo() async {
        await config.seed(WorkspaceFixtures.uiState(openTabs: ["/r/alpha"], activeTab: "/r/alpha"))
        var changes: [RepoChange] = []
        navigation.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        shared.loadWorkspace(state: await config.uiState(), repos: repos)
        XCTAssertEqual(changes, [RepoChange(old: nil, new: "/r/alpha")])
    }

    func testSetActiveTabAnnouncesOnlyRealSwitches() {
        navigation.openTab("/r/alpha")
        var changes: [RepoChange] = []
        navigation.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        navigation.setRoute(.repo("/r/alpha")) // aynı tab → sinyal yok
        XCTAssertEqual(changes, [])

        navigation.setRoute(.repo("/r/beta"))
        XCTAssertEqual(changes, [RepoChange(old: "/r/alpha", new: "/r/beta")])
    }

    func testClosingInactiveTabSignalsUnwatchWithNilDestination() {
        navigation.openTab("/r/alpha")
        navigation.openTab("/r/beta") // aktif = beta
        var changes: [RepoChange] = []
        navigation.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        navigation.requestCloseTab("/r/alpha")

        XCTAssertEqual(navigation.activeRepoPath, "/r/beta", "aktif tab değişmez")
        XCTAssertEqual(
            changes, [RepoChange(old: "/r/alpha", new: nil)],
            "kapanan repo unwatch için nil hedefiyle bildirilir"
        )
    }

    func testClosingActiveTabSignalsSwitchToNewActive() {
        navigation.openTab("/r/alpha")
        navigation.openTab("/r/beta")
        navigation.setRoute(.repo("/r/beta"))
        var changes: [RepoChange] = []
        navigation.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        navigation.requestCloseTab("/r/beta")
        XCTAssertEqual(changes, [RepoChange(old: "/r/beta", new: "/r/alpha")])
    }

    func testClosingLastTabSignalsNilDestination() {
        navigation.openTab("/r/alpha")
        var changes: [RepoChange] = []
        navigation.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        navigation.requestCloseTab("/r/alpha")
        XCTAssertNil(navigation.activeRepoPath)
        XCTAssertEqual(changes, [RepoChange(old: "/r/alpha", new: nil)])
    }
}
