import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Faz 6.3 route geçiş sözleşmesi — **view'da değil store'da**.
///
/// | Geçiş | Terminal yüzeyi | View köprüsü |
/// |---|---|---|
/// | terminals → başka route | arka plan, odak yok | `detachAll()` |
/// | başka route → terminals | foreground + odak | `refreshAttachedViews()` |
/// | repo → repo | eskisi arkaya, yenisi öne | — |
///
/// PTY hiçbir adımda durmaz; view'lar yok EDİLMEZ, yalnız detach olur.
@MainActor
final class RouteTransitionTests: XCTestCase {
    private var config: FakeConfigService!
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var viewProvider: FakeTerminalViewProvider!
    private var navigation: NavigationStore!

    private let tasks = WorkspaceRoute.content(ContentRouteID("placeholder"))

    override func setUp() async throws {
        config = FakeConfigService()
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        viewProvider = FakeTerminalViewProvider()
        navigation = NavigationStore(config: config, terminals: terminals, viewProvider: viewProvider)
    }

    @discardableResult
    private func spawn(_ name: String, repo: String = "/r/alpha") -> TerminalMeta {
        let meta = WorkspaceFixtures.meta(name, repo: repo)
        terminals.apply(.spawned(meta))
        return meta
    }

    /// Repo GENELİNDEKİ yüzey geçişleri (tekil kart çağrıları hariç).
    private var repoSurfaceStates: [TerminalSurfaceState] {
        service.surfaceStateCalls.compactMap { $0.repoPath == nil ? nil : $0.state }
    }

    // MARK: - Çıkış

    func testLeavingTerminalsBackgroundsSurfaceAndDetachesViews() {
        let meta = spawn("t1")
        navigation.openTab("/r/alpha")
        terminals.focus(meta.id)
        service.resetSurfaceStateCalls()

        navigation.setRoute(tasks)

        XCTAssertEqual(repoSurfaceStates, [.background], "repo yüzeyi arkaya düşer")
        XCTAssertEqual(service.focusCalls.last, TerminalID?.none, "arka plandayken servis odağı bırakılır")
        XCTAssertEqual(terminals.activeTerminalID, meta.id, "kullanıcı seçimi korunur")
        XCTAssertEqual(viewProvider.detachAllCount, 1)
    }

    func testLeavingTerminalsDoesNotKillOrResizeAnything() {
        spawn("t1")
        navigation.openTab("/r/alpha")
        navigation.setRoute(tasks)

        XCTAssertTrue(service.killedIDs.isEmpty, "PTY çalışmaya devam eder")
        XCTAssertEqual(terminals.totalCount, 1)
    }

    func testLeavingTwiceDetachesOnlyOnce() {
        navigation.openTab("/r/alpha")
        navigation.setRoute(tasks)
        navigation.setRoute(.content(ContentRouteID("other")))
        XCTAssertEqual(viewProvider.detachAllCount, 1)
    }

    // MARK: - Dönüş

    func testReturningToSameRepoForegroundsAndRefreshes() {
        let meta = spawn("t1")
        navigation.openTab("/r/alpha")
        terminals.focus(meta.id)
        navigation.setRoute(tasks)
        service.resetSurfaceStateCalls()

        navigation.setRoute(.repo("/r/alpha"))

        XCTAssertEqual(repoSurfaceStates, [.foreground], "aynı repoya dönüşte de foreground uygulanır")
        XCTAssertEqual(service.focusCalls.last, meta.id)
        XCTAssertEqual(viewProvider.refreshCallCount, 1)
        XCTAssertEqual(viewProvider.detachAllCount, 1, "dönüşte tekrar detach edilmez")
    }

    func testReturningToAnotherRepoAlsoRefreshes() {
        spawn("t1")
        spawn("t2", repo: "/r/beta")
        navigation.openTab("/r/alpha")
        navigation.setRoute(tasks)

        navigation.setRoute(.repo("/r/beta"))
        XCTAssertEqual(viewProvider.refreshCallCount, 1)
    }

    /// Ara route'tayken restore/spawn olan bir terminal ÖNE ALINMAZ — yüzey
    /// hâlâ arka plandadır.
    func testRestoreWhileOffRouteDoesNotForegroundTheSurface() {
        let meta = spawn("t1")
        navigation.openTab("/r/alpha")
        terminals.minimize(meta.id)
        navigation.setRoute(tasks)
        service.resetSurfaceStateCalls()

        terminals.restore(meta.id)
        XCTAssertFalse(repoSurfaceStates.contains(.foreground), "route dışındayken öne alma yok")
    }

    // MARK: - Repo ↔ repo (view köprüsüne dokunulmaz)

    func testRepoToRepoSwitchKeepsViewBridgeUntouched() {
        spawn("t1")
        spawn("t2", repo: "/r/beta")
        navigation.openTab("/r/alpha")
        navigation.openTab("/r/beta")

        XCTAssertEqual(viewProvider.detachAllCount, 0, "SwiftUI host'ları yerinde kalır")
        XCTAssertEqual(viewProvider.refreshCallCount, 0)
    }

    func testNavigationWorksWithoutAViewProvider() {
        let headless = NavigationStore(config: config, terminals: terminals)
        headless.openTab("/r/alpha")
        headless.setRoute(tasks)
        headless.setRoute(.repo("/r/alpha"))
        XCTAssertEqual(headless.activeRoute, .repo("/r/alpha"), "köprü opsiyoneldir")
    }
}
