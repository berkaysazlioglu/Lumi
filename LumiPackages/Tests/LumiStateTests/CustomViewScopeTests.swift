import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 135: Custom View yüzeyi — store'un kapsam seçicileri, yüzey geçişi,
/// odak komşuluğu, view'a terminal açma ve boş view'ın silinmesi.
@MainActor
final class CustomViewScopeTests: XCTestCase {
    private var config: FakeConfigService!
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var navigation: NavigationStore!
    private var layout: LayoutStore!

    override func setUp() async throws {
        config = FakeConfigService()
        service = FakeTerminalService()
        let shared = SharedStores.make(config: config, terminal: service, toastAutoDismissAfter: 60)
        terminals = shared.terminals
        layout = shared.layout
        navigation = NavigationStore(config: config, terminals: terminals, viewProvider: FakeTerminalViewProvider())
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

    private func makeView(_ metas: TerminalMeta...) -> CustomViewID {
        let view = terminals.createCustomView(with: metas[0].id)!
        metas.dropFirst().forEach { terminals.addToCustomView($0.id, view) }
        return view
    }

    // MARK: - Seçiciler

    func testViewListsOnlyItsMembersAcrossProjects() {
        let a1 = spawn("a1")
        spawn("a2")
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(b1, a1)
        terminals.minimize(a1.id)

        XCTAssertEqual(names(terminals.terminals(in: .custom(view))), ["b1", "a1"])
        XCTAssertEqual(names(terminals.visibleTerminals(in: .custom(view))), ["b1"])
        XCTAssertEqual(names(terminals.minimizedTerminals(in: .custom(view))), ["a1"])
        XCTAssertTrue(terminals.contains(a1, in: .custom(view)))
        XCTAssertFalse(terminals.contains(terminals.terminals[1], in: .custom(view)))
    }

    func testCreatingAViewGeneratesADistinctNameAndSignalsPersistence() {
        let a1 = spawn("a1")
        var changes = 0
        terminals.onOrderChanged = { changes += 1 }

        let first = terminals.createCustomView(with: a1.id)!
        let second = terminals.createCustomView(with: a1.id)!

        let viewNames = terminals.customViews.views.map(\.name)
        XCTAssertEqual(Set(viewNames).count, 2)
        XCTAssertEqual(terminals.customViews(containing: a1.id).map(\.id), [first, second])
        XCTAssertEqual(changes, 2)
        XCTAssertNil(terminals.createCustomView(with: TerminalID()), "bilinmeyen terminalden view doğmaz")
    }

    func testSwapInViewLeavesOtherOrdersUntouched() {
        let a1 = spawn("a1")
        let a2 = spawn("a2")
        let view = makeView(a1, a2)

        terminals.swap(a1.id, a2.id, in: .custom(view))

        XCTAssertEqual(names(terminals.terminals(in: .custom(view))), ["a2", "a1"])
        XCTAssertEqual(names(terminals.terminals), ["a1", "a2"])
        XCTAssertEqual(names(terminals.terminals(in: .all)), ["a1", "a2"])
    }

    // MARK: - Boş view yoktur

    func testRemovingFromViewKeepsTheTerminalAndLastRemovalDeletesTheView() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(a1, b1)
        var removed: [CustomViewID] = []
        terminals.onCustomViewsRemoved = { removed += $0 }

        terminals.removeFromCustomView(a1.id, view)
        XCTAssertNotNil(terminals.meta(for: a1.id), "terminal kapanmaz")
        XCTAssertTrue(removed.isEmpty)

        terminals.removeFromCustomView(b1.id, view)
        XCTAssertEqual(removed, [view])
        XCTAssertNil(terminals.customViews.view(view))
    }

    func testClosingTheLastMemberDeletesTheView() {
        let a1 = spawn("a1")
        let view = makeView(a1)
        var removed: [CustomViewID] = []
        terminals.onCustomViewsRemoved = { removed += $0 }

        terminals.apply(.exited(a1.id, code: 0))

        XCTAssertEqual(removed, [view])
    }

    // MARK: - View'a terminal açma

    func testSpawnAnchorPrefersActiveMemberThenLastActiveMember() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        let outsider = spawn("x", repo: "/r/gamma")
        let view = makeView(a1, b1)

        terminals.focus(b1.id)
        XCTAssertEqual(terminals.spawnAnchor(in: view)?.id, b1.id)

        terminals.focus(outsider.id)
        XCTAssertEqual(terminals.spawnAnchor(in: view)?.id, b1.id, "üye olmayan aktif terminal çapa olmaz")
    }

    func testTerminalSpawnedIntoViewJoinsOnSpawnedEvent() throws {
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(b1)
        var changes = 0
        terminals.onOrderChanged = { changes += 1 }

        let anchor = try XCTUnwrap(terminals.spawnAnchor(in: view))
        let spawned = try XCTUnwrap(terminals.spawn(in: anchor.repoPath, command: "claude", joining: view))
        XCTAssertEqual(spawned.repoPath, "/r/beta", "çapanın checkout'unda doğar")
        XCTAssertFalse(terminals.contains(spawned, in: .custom(view)), "store tanımadan üye yazılmaz")

        terminals.apply(.spawned(spawned))

        XCTAssertEqual(terminals.terminals(in: .custom(view)).map(\.id), [b1.id, spawned.id])
        XCTAssertEqual(changes, 1)
    }

    // MARK: - Yüzey ve odak

    func testEnteringAViewForegroundsOnlyItsMembers() {
        let a1 = spawn("a1")
        let a2 = spawn("a2")
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(a1, b1)
        navigation.openTab("/r/alpha")
        service.resetSurfaceStateCalls()

        navigation.setRoute(WorkspaceRoute.content(.customView(view)))

        let calls = service.surfaceStateCalls
        XCTAssertEqual(calls.first, .init(state: .background, id: nil, repoPath: "/r/alpha"), "önceki repo arkaya")
        let foregrounded = Set(calls.filter { $0.state == .foreground }.compactMap(\.id))
        XCTAssertEqual(foregrounded, [a1.id, b1.id])
        XCTAssertFalse(foregrounded.contains(a2.id))
    }

    func testLeavingAViewBackgroundsItsMembers() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(a1, b1)
        navigation.setRoute(WorkspaceRoute.content(.customView(view)))
        service.resetSurfaceStateCalls()

        navigation.openTab("/r/beta")

        let backgrounded = Set(service.surfaceStateCalls.filter { $0.state == .background }.compactMap(\.id))
        XCTAssertEqual(backgrounded, [a1.id, b1.id])
        XCTAssertEqual(service.surfaceStateCalls.last, .init(state: .foreground, id: nil, repoPath: "/r/beta"))
    }

    func testMinimizingFocusesTheNeighborInsideTheView() {
        let a1 = spawn("a1")
        spawn("a2")
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(a1, b1)
        navigation.setRoute(WorkspaceRoute.content(.customView(view)))
        terminals.focus(b1.id)

        terminals.minimize(b1.id)

        XCTAssertEqual(terminals.activeTerminalID, a1.id, "komşu view'ın içinden — a2 üye değil")
    }

    func testRestoreForegroundsAMemberWhileTheViewIsVisible() {
        let a1 = spawn("a1")
        let view = makeView(a1)
        terminals.minimize(a1.id)
        navigation.setRoute(WorkspaceRoute.content(.customView(view)))
        service.resetSurfaceStateCalls()

        terminals.restore(a1.id)

        XCTAssertEqual(service.surfaceStateCalls.last, .init(state: .foreground, id: a1.id, repoPath: nil))
    }

    func testReturningToTheViewFocusesItsLastActiveMember() {
        let a1 = spawn("a1")
        let b1 = spawn("b1", repo: "/r/beta")
        let view = makeView(a1, b1)
        navigation.setRoute(WorkspaceRoute.content(.customView(view)))
        terminals.focus(b1.id)
        navigation.openTab("/r/alpha")
        XCTAssertEqual(terminals.activeTerminalID, a1.id)

        navigation.setRoute(WorkspaceRoute.content(.customView(view)))

        XCTAssertEqual(terminals.activeTerminalID, a1.id, "aktif terminal üyeyse o korunur")
        terminals.focus(spawn("x", repo: "/r/gamma").id)
        navigation.openTab("/r/gamma")
        navigation.setRoute(WorkspaceRoute.content(.customView(view)))
        XCTAssertEqual(terminals.activeTerminalID, a1.id, "son aktif üye")
    }

    // MARK: - Layout

    func testMaximizeAndGridAreKeptPerViewAndForgottenWithIt() {
        let a1 = spawn("a1")
        let view = makeView(a1)
        let grid = GridLayout(mode: .columns, count: 2, heightMode: .fit)

        XCTAssertTrue(layout.maximize(a1.id, in: .custom(view)))
        layout.setGridLayout(grid, for: .custom(view))
        XCTAssertNil(layout.maximizedTerminal(in: .all))
        XCTAssertEqual(layout.gridLayout(for: .custom(view)), grid)
        XCTAssertEqual(layout.gridLayout(for: .all), LayoutStore.defaultGridLayout)

        layout.forgetCustomViews([view])

        XCTAssertNil(layout.maximizedTerminal(in: .custom(view)))
        XCTAssertEqual(layout.gridLayout(for: .custom(view)), LayoutStore.defaultGridLayout)
    }

    func testPruneDropsLayoutsOfMissingViews() {
        let kept = CustomViewID(rawValue: "kept")
        let gone = CustomViewID(rawValue: "gone")
        let grid = GridLayout(mode: .columns, count: 3, heightMode: .fit)
        layout.setGridLayout(grid, for: .custom(kept))
        layout.setGridLayout(grid, for: .custom(gone))

        layout.pruneCustomViewLayouts(keeping: [kept])

        XCTAssertEqual(Set(layout.customViewGridLayouts.keys), [kept])
    }

    // MARK: - Açılış

    func testRestoredViewsPlaceResumedSessionsAndDropTheDead() {
        var removed: [CustomViewID] = []
        terminals.onCustomViewsRemoved = { removed += $0 }
        terminals.restoreCustomViews([
            CustomViewState(id: "v-1", name: "Live", order: ["s-2", "s-1"]),
            CustomViewState(id: "v-2", name: "Dead", order: ["s-9"]),
        ])
        let first = spawn("first", claude: "s-1")
        let second = spawn("second", repo: "/r/beta", claude: "s-2")

        terminals.finishCustomViewRestore(aliveTerminals: [first, second])

        XCTAssertEqual(removed, [CustomViewID(rawValue: "v-2")])
        XCTAssertEqual(names(terminals.terminals(in: .custom(CustomViewID(rawValue: "v-1")))), ["second", "first"])
    }
}
