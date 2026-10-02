import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiAppCore

/// Menü komutlarının store'lara BAĞLANMA davranışı (karar 59).
///
/// `MenuActionDispatcherTests` yalnız yönlendirmeyi (id → closure) kilitler;
/// burası closure'ın gerçekten ne yaptığını kilitler — repo tab'ları ile
/// terminal odağının iki ayrı eksen olduğu ve ⌘W'nin terminal yokken tab'a
/// düştüğü sözleşme.
@MainActor
final class AppMenuCommandsTests: XCTestCase {
    private var dispatcher: MenuActionDispatcher!
    private var closeProjectCount = 0
    private var shared: SharedStores!
    private var terminalService: FakeTerminalService!

    override func setUp() async throws {
        terminalService = FakeTerminalService()
        shared = SharedStores.make(
            config: FakeConfigService(),
            terminal: terminalService,
            viewProvider: FakeTerminalViewProvider(),
            toastAutoDismissAfter: 60
        )
        dispatcher = MenuActionDispatcher()
        closeProjectCount = 0
        AppMenuCommands.register(
            in: dispatcher,
            shared: shared,
            openSettings: {},
            openAbout: {},
            closeActiveProject: { [weak self] in self?.closeProjectCount += 1 }
        )
        // Terminal listesi servis stream'inden akar: lifecycle başlamadan
        // spawn edilen terminal store'a düşmez.
        await shared.terminals.start()
    }

    override func tearDown() async throws {
        shared.terminals.stop()
    }

    // MARK: - ⌃1…⌃9 repo tab'ını değiştirir

    /// Karar 65: indeks AÇIK TAB'lara değil, PROJELER listesine vurur —
    /// kullanıcının gerçekten gördüğü liste odur.
    func testSwitchToProjectActivatesTheProjectAtTheGivenIndex() {
        wireProjects(["/r/alpha", "/r/beta", "/r/gamma"])

        dispatcher.perform(.switchToProjectAtIndex, index: 2)

        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/beta")
    }

    /// Proje sayısından büyük indeks sessizce yutulur — aktif olanı DEĞİŞTİRMEZ.
    func testSwitchToProjectIgnoresIndexBeyondProjectCount() {
        wireProjects(["/r/alpha", "/r/beta"])
        dispatcher.perform(.switchToProjectAtIndex, index: 1)

        dispatcher.perform(.switchToProjectAtIndex, index: 9)

        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/alpha")
    }

    /// Bir projeye dönünce, o projede EN SON kullanılan checkout açılır —
    /// projenin kökü değil (karar 65).
    func testSwitchToProjectReopensTheLastUsedCheckout() {
        wireProjects(["/r/alpha", "/r/beta"], checkouts: ["/r/alpha": ["/r/alpha/wt"]])
        shared.navigation.openTab("/r/alpha/wt")   // alpha'da worktree kullanıldı
        dispatcher.perform(.switchToProjectAtIndex, index: 2)

        dispatcher.perform(.switchToProjectAtIndex, index: 1)

        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/alpha/wt")
    }

    /// Hatırlanan checkout artık projeye ait değilse (worktree silinmiş)
    /// projenin köküne düşülür — ölü bir yola gidilmez.
    func testSwitchToProjectFallsBackWhenRememberedCheckoutIsGone() {
        wireProjects(["/r/alpha"], checkouts: ["/r/alpha": ["/r/alpha/wt"]])
        shared.navigation.openTab("/r/alpha/wt")
        wireProjects(["/r/alpha"])                 // worktree kayboldu
        shared.navigation.setRoute(.none)

        dispatcher.perform(.switchToProjectAtIndex, index: 1)

        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/alpha")
    }

    /// Proje köprüsü enjekte edilmemişse (proje feature'ı olmayan kompozisyon)
    /// komut sessizce hiçbir şey yapmaz — çökmez.
    func testSwitchToProjectIsInertWithoutProjectBridge() {
        shared.navigation.openTab("/r/alpha")

        dispatcher.perform(.switchToProjectAtIndex, index: 1)

        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/alpha")
    }

    private func wireProjects(_ projects: [String], checkouts: [String: [String]] = [:]) {
        shared.navigation.projectOrder = { projects }
        shared.navigation.projectCheckouts = { [$0] + (checkouts[$0] ?? []) }
    }

    /// İki indeksli aile aynı eksende DEĞİL: ⌘N terminal odaklar, tab'a
    /// dokunmaz.
    func testFocusTerminalAtIndexDoesNotChangeTheActiveTab() {
        shared.navigation.openTab("/r/alpha")
        shared.navigation.openTab("/r/beta")

        dispatcher.perform(.focusTerminalAtIndex, index: 1)

        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/beta")
    }

    // MARK: - ⌘W

    func testCloseTerminalClosesTheActiveTerminalWhenThereIsOne() async throws {
        shared.navigation.openTab("/r/alpha")
        shared.terminals.spawn(in: "/r/alpha", command: nil)
        await waitUntil("terminal store'a düşmedi") { self.shared.terminals.activeTerminalID != nil }
        let id = try XCTUnwrap(shared.terminals.activeTerminalID)

        dispatcher.perform(.closeTerminal)

        XCTAssertEqual(terminalService.killedIDs, [id])
        XCTAssertEqual(shared.navigation.openTabs, ["/r/alpha"], "tab kapanmamalı")
    }

    /// Electron paritesi: terminal yoksa ⌘W repo TAB'ını kapatır.
    func testCloseTerminalClosesTheActiveTabWhenNoTerminalIsOpen() {
        shared.navigation.openTab("/r/alpha")
        shared.navigation.openTab("/r/beta")

        dispatcher.perform(.closeTerminal)

        XCTAssertEqual(shared.navigation.openTabs, ["/r/alpha"])
        XCTAssertEqual(shared.navigation.activeRepoPath, "/r/alpha")
    }

    /// Hiç tab yokken ⌘W hiçbir şey yapmaz (pencere KAPANMAZ — menü
    /// interception'ın tüm amacı bu).
    func testCloseTerminalIsANoOpWithoutTerminalsOrTabs() {
        dispatcher.perform(.closeTerminal)

        XCTAssertTrue(shared.navigation.openTabs.isEmpty)
        XCTAssertTrue(terminalService.killedIDs.isEmpty)
    }

    /// Karar 66: ⇧⌘W ayrı bir komuttur ve enjekte edilen aksiyonu çağırır —
    /// kaldırma `repos`+`workspaces` gerektirir, `SharedStores`'ta yokturlar.
    func testCloseProjectInvokesTheInjectedAction() {
        dispatcher.perform(.closeProject, index: nil)
        XCTAssertEqual(closeProjectCount, 1)
    }

    /// ⌘W ile ⇧⌘W AYRI komutlardır: ⌘W projeyi kaldırmaz.
    func testCloseTerminalDoesNotRemoveTheProject() {
        shared.navigation.openTab("/r/alpha")

        dispatcher.perform(.closeTerminal, index: nil)

        XCTAssertEqual(closeProjectCount, 0)
    }
}
