import Foundation
import XCTest
import LumiKit
import LumiTestSupport
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

    // MARK: - Sidebar toggle → persist (karakterizasyon 2.5)

    func testToggleLeftSidebarFlipsAndPersists() async throws {
        XCTAssertTrue(store.leftSidebarOpen, "default açık")

        store.toggleLeftSidebar()
        XCTAssertFalse(store.leftSidebarOpen)
        try await waitForPersist()
        var persisted = await config.uiState()
        XCTAssertFalse(persisted.leftSidebarOpen)

        store.toggleLeftSidebar()
        try await waitForPersist(minimumCount: 2)
        persisted = await config.uiState()
        XCTAssertTrue(persisted.leftSidebarOpen)
    }

    func testToggleRightSidebarFlipsAndPersists() async throws {
        XCTAssertFalse(store.rightSidebarOpen, "default kapalı")

        store.toggleRightSidebar()
        XCTAssertTrue(store.rightSidebarOpen)
        try await waitForPersist()
        let persisted = await config.uiState()
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    func testSidebarTogglesAreIndependent() async throws {
        store.toggleRightSidebar()
        try await waitForPersist()
        XCTAssertTrue(store.leftSidebarOpen, "sağ toggle solu etkilemez")
        let persisted = await config.uiState()
        XCTAssertTrue(persisted.leftSidebarOpen)
        XCTAssertTrue(persisted.rightSidebarOpen)
    }

    func testSetSidebarOpenPersistsOnlyRealChanges() async throws {
        // Aynı değere set → guard → yazım YOK (idempotent setter)
        store.setLeftSidebarOpen(true)
        store.setRightSidebarOpen(false)
        try await Task.sleep(for: .milliseconds(50))
        var writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0, "değişmeyen setter persist etmez")

        store.setLeftSidebarOpen(false)
        try await waitForPersist()
        writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 1)

        // Yeni değerin tekrarı da yazmaz
        store.setLeftSidebarOpen(false)
        try await Task.sleep(for: .milliseconds(50))
        writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 1)
    }

    // MARK: - UIState round-trip (load → değiştir → persist → yeniden load)

    func testUIStateRoundTripsThroughConfigService() async throws {
        await config.seed(UIState(
            openTabs: ["/r/alpha"],
            activeTab: "/r/alpha",
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil
        ))
        await store.load(repos: repos)

        store.openTab("/r/beta")
        store.setGridLayout(GridLayout(mode: .columns, count: 3, heightMode: .fit), for: "/r/beta")
        store.toggleLeftSidebar()
        store.toggleRightSidebar()
        try await waitForPersist(minimumCount: 4)

        // Aynı config üzerinden TAZE bir store: diskteki hal geri okunmalı
        let reloaded = WorkspaceStore(config: config, terminals: terminals)
        await reloaded.load(repos: repos)

        XCTAssertEqual(reloaded.openTabs, ["/r/alpha", "/r/beta"])
        XCTAssertEqual(reloaded.activeTab, "/r/beta")
        XCTAssertFalse(reloaded.leftSidebarOpen)
        XCTAssertTrue(reloaded.rightSidebarOpen)
        XCTAssertEqual(
            reloaded.gridLayout(for: "/r/beta"),
            GridLayout(mode: .columns, count: 3, heightMode: .fit)
        )
    }

    /// Oturumluk alanlar (focus mode, maximize, repo selector) persist EDİLMEZ.
    func testSessionOnlyStateIsNotPersisted() async throws {
        store.openTab("/r/alpha")
        let a = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(a))
        store.maximize(a.id, in: "/r/alpha")
        store.toggleFocusMode()
        store.isRepoSelectorOpen = true
        try await waitForPersist()

        let reloaded = WorkspaceStore(config: config, terminals: terminals)
        await reloaded.load(repos: repos)
        XCTAssertFalse(reloaded.isFocusMode)
        XCTAssertNil(reloaded.maximizedTerminal(in: "/r/alpha"))
        XCTAssertFalse(reloaded.isRepoSelectorOpen)
    }

    // MARK: - Focus mode köprüsü

    func testToggleFocusModeNotifiesBridgeBothWays() {
        var events: [Bool] = []
        store.onFocusModeChanged = { events.append($0) }

        store.toggleFocusMode()
        XCTAssertTrue(store.isFocusMode)
        store.toggleFocusMode()
        XCTAssertFalse(store.isFocusMode)
        XCTAssertEqual(events, [true, false])
    }

    func testExitFocusModeNotifiesOnlyWhenActive() {
        var events: [Bool] = []
        store.onFocusModeChanged = { events.append($0) }

        store.exitFocusMode() // zaten kapalı → guard
        XCTAssertEqual(events, [], "kapalıyken exit köprüyü tetiklemez")

        store.toggleFocusMode()
        store.exitFocusMode()
        XCTAssertFalse(store.isFocusMode)
        XCTAssertEqual(events, [true, false])
    }

    func testFocusModeIsNotPersisted() async throws {
        store.toggleFocusMode()
        try await Task.sleep(for: .milliseconds(50))
        let writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0, "focus mode oturumluk — disk yazımı yok")
    }

    // MARK: - Quit dialog (.terminateLater akışı)

    func testResolveQuitTrueClearsDialogAndReportsDecision() {
        var decisions: [Bool] = []
        store.onQuitResolved = { decisions.append($0) }

        store.presentQuitDialog(terminalCount: 3)
        XCTAssertEqual(store.quitDialogTerminalCount, 3)
        XCTAssertTrue(decisions.isEmpty, "dialog açılırken karar bildirilmez")

        store.resolveQuit(true)
        XCTAssertNil(store.quitDialogTerminalCount)
        XCTAssertEqual(decisions, [true])
    }

    func testResolveQuitFalseAlsoClearsDialog() {
        var decisions: [Bool] = []
        store.onQuitResolved = { decisions.append($0) }

        store.presentQuitDialog(terminalCount: 1)
        store.resolveQuit(false)
        XCTAssertNil(store.quitDialogTerminalCount)
        XCTAssertEqual(decisions, [false])
    }

    func testPresentQuitDialogWithZeroTerminalsStillOpens() {
        // Guard store'da değil çağıranda: 0 da geçerli bir sunum durumudur.
        store.presentQuitDialog(terminalCount: 0)
        XCTAssertEqual(store.quitDialogTerminalCount, 0)
    }

    // MARK: - onActiveRepoChanged (watch/unwatch köprüsü)

    private struct RepoChange: Equatable {
        let old: String?
        let new: String?
    }

    func testLoadAnnouncesInitialActiveRepo() async {
        await config.seed(UIState(
            openTabs: ["/r/alpha"],
            activeTab: "/r/alpha",
            leftSidebarOpen: true,
            rightSidebarOpen: false,
            projectGridLayouts: [:],
            windowBounds: nil,
            windowMaximized: nil
        ))
        var changes: [RepoChange] = []
        store.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        await store.load(repos: repos)
        XCTAssertEqual(changes, [RepoChange(old: nil, new: "/r/alpha")])
    }

    func testSetActiveTabAnnouncesOnlyRealSwitches() {
        store.openTab("/r/alpha")
        var changes: [RepoChange] = []
        store.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        store.setActiveTab("/r/alpha") // aynı tab → sinyal yok
        XCTAssertEqual(changes, [])

        store.setActiveTab("/r/beta")
        XCTAssertEqual(changes, [RepoChange(old: "/r/alpha", new: "/r/beta")])
    }

    func testClosingInactiveTabSignalsUnwatchWithNilDestination() {
        store.openTab("/r/alpha")
        store.openTab("/r/beta") // aktif = beta
        var changes: [RepoChange] = []
        store.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        store.requestCloseTab("/r/alpha", repoName: "alpha")

        XCTAssertEqual(store.activeTab, "/r/beta", "aktif tab değişmez")
        XCTAssertEqual(
            changes, [RepoChange(old: "/r/alpha", new: nil)],
            "kapanan repo unwatch için nil hedefiyle bildirilir"
        )
    }

    func testClosingActiveTabSignalsSwitchToNewActive() {
        store.openTab("/r/alpha")
        store.openTab("/r/beta")
        store.setActiveTab("/r/beta")
        var changes: [RepoChange] = []
        store.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        store.requestCloseTab("/r/beta", repoName: "beta")
        XCTAssertEqual(changes, [RepoChange(old: "/r/beta", new: "/r/alpha")])
    }

    func testClosingLastTabSignalsNilDestination() {
        store.openTab("/r/alpha")
        var changes: [RepoChange] = []
        store.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        store.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertNil(store.activeTab)
        XCTAssertEqual(changes, [RepoChange(old: "/r/alpha", new: nil)])
    }

    func testConfirmCloseTabAlsoSignalsUnwatch() {
        store.openTab("/r/alpha")
        store.openTab("/r/beta")
        let meta = TerminalMeta(id: TerminalID(), name: "t1", repoPath: "/r/alpha", createdAt: Date())
        terminals.apply(.spawned(meta))
        terminals.minimize(meta.id)
        var changes: [RepoChange] = []
        store.onActiveRepoChanged = { changes.append(RepoChange(old: $0, new: $1)) }

        store.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertEqual(changes, [], "dialog açıkken henüz sinyal yok")

        store.confirmCloseTab()
        XCTAssertEqual(changes, [RepoChange(old: "/r/alpha", new: nil)])
    }
}
