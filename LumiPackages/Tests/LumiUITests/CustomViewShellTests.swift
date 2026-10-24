import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiUI

/// Karar 135: Custom View'ların `ShellContext` yüzü — oluşturma, view'a terminal
/// açma (çapa checkout'u), hedef etiketi/seçimi ve Projects'ten seçimde view'da
/// kalma.
@MainActor
final class CustomViewShellTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func setUp() async throws {
        let repos = FakeRepoService()
        await repos.setRepos([
            Repo(name: "Game", path: "/projects/game", isGitRepo: true, source: .projectsRoot),
            Repo(name: "Tools", path: "/projects/tools", isGitRepo: true, source: .projectsRoot),
        ])
        fixture = await ShellContextFixture.make(repo: repos)
        await shell.repos.reload()
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    private func waitForTerminalCount(_ count: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while shell.terminals.terminals.count < count {
            if Date() > deadline { throw ShellFixtureError.terminalDidNotAppear }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testNewViewCopiesTheFirstTerminalsProjectLayoutAndIsHighlighted() async throws {
        let game = try await fixture.spawnTerminal(in: "/projects/game")
        let projectLayout = GridLayout(mode: .columns, count: 3, heightMode: .scroll, heightRatio: .half)
        shell.layout.setGridLayout(projectLayout, for: "/projects/game")

        shell.addToNewCustomView(game.id)

        let view = try XCTUnwrap(shell.terminals.customViews.views.first?.id)
        XCTAssertEqual(shell.layout.gridLayout(for: .custom(view)), projectLayout)
        XCTAssertEqual(shell.highlightedCustomView, view)
    }

    func testRightPanelTargetsTheSelectedTerminalsCheckoutOnAllTerminals() async throws {
        shell.navigation.openTab("/projects/game")
        let game = try await fixture.spawnTerminal(in: "/projects/game")
        shell.navigation.setRoute(AllTerminalsRoute.route)
        shell.terminals.focus(game.id)

        XCTAssertEqual(shell.toolsRepoPath, "/projects/game")
        XCTAssertNil(shell.activeRepoPath, "repo eylemleri (hızlı komutlar, Files) kapalı kalır")
    }

    func testNewViewGetsARandomNameAndAToast() async throws {
        let game = try await fixture.spawnTerminal(in: "/projects/game")

        shell.addToNewCustomView(game.id)

        let view = try XCTUnwrap(shell.terminals.customViews.views.first)
        XCTAssertFalse(view.name.isEmpty)
        XCTAssertTrue(shell.toasts.toasts.contains { $0.title == "Created view \(view.name)" })
        XCTAssertEqual(shell.terminals.terminals(in: .custom(view.id)).map(\.id), [game.id])
    }

    func testSpawningInAViewOpensInTheActiveMembersCheckoutAndJoinsTheView() async throws {
        let game = try await fixture.spawnTerminal(named: "game", in: "/projects/game")
        let tools = try await fixture.spawnTerminal(named: "tools", in: "/projects/tools")
        let view = try XCTUnwrap(shell.terminals.createCustomView(with: game.id))
        shell.terminals.addToCustomView(tools.id, view)
        shell.navigation.setRoute(CustomViewRoute.route(view))
        shell.terminals.focus(tools.id)
        XCTAssertEqual(NewTerminalMenu.locationLabel(shell: shell, scope: .custom(view)), "Tools")

        shell.spawnTerminal(in: .custom(view), command: "claude")
        try await waitForTerminalCount(3)

        let spawned = try XCTUnwrap(shell.terminals.terminals.last)
        XCTAssertEqual(spawned.repoPath, "/projects/tools", "çapanın checkout'unda — o projeye ait")
        XCTAssertEqual(shell.terminals.terminals(in: .custom(view)).map(\.id), [game.id, tools.id, spawned.id])
    }

    func testLocationItemsListTheViewsCheckoutsAndSelectingOneMovesTheAnchor() async throws {
        let game = try await fixture.spawnTerminal(named: "game", in: "/projects/game")
        let tools = try await fixture.spawnTerminal(named: "tools", in: "/projects/tools")
        let view = try XCTUnwrap(shell.terminals.createCustomView(with: game.id))
        shell.terminals.addToCustomView(tools.id, view)
        shell.terminals.focus(game.id)

        let items = NewTerminalMenu.locationItems(shell: shell, scope: .custom(view))
        XCTAssertEqual(items.map(\.label), ["Game", "Tools"])
        XCTAssertEqual(items.map(\.isSelected), [true, false])

        items[1].action()

        XCTAssertEqual(shell.terminals.spawnAnchor(in: view)?.id, tools.id)
    }

    func testSelectingAMemberFromProjectsStaysInTheView() async throws {
        let game = try await fixture.spawnTerminal(named: "game", in: "/projects/game")
        let tools = try await fixture.spawnTerminal(named: "tools", in: "/projects/tools")
        // Proje checkout'u sayılsın (serbest yol All Terminals'a gider, karar 108).
        shell.navigation.openTab("/projects/tools")
        let view = try XCTUnwrap(shell.terminals.createCustomView(with: game.id))
        let route = CustomViewRoute.route(view)
        shell.navigation.setRoute(route)

        shell.focusAgent(game)
        XCTAssertEqual(shell.navigation.activeRoute, route, "üye view'dan çıkmadan öne gelir")
        XCTAssertEqual(shell.terminals.activeTerminalID, game.id)

        shell.focusAgent(tools)
        XCTAssertEqual(shell.navigation.activeRoute, .repo("/projects/tools"), "üye olmayan kendi repo'suna gider")
    }

    func testRemoveFromViewIsOfferedOnlyInsideTheView() async throws {
        let game = try await fixture.spawnTerminal(in: "/projects/game")
        let view = try XCTUnwrap(shell.terminals.createCustomView(with: game.id))

        XCTAssertNil(shell.activeCustomView(containing: game.id))
        shell.navigation.setRoute(CustomViewRoute.route(view))
        XCTAssertEqual(shell.activeCustomView(containing: game.id), view)
        XCTAssertEqual(shell.activeCustomViewName, shell.terminals.customViews.view(view)?.name)
    }

    func testDeletingAViewKeepsItsTerminals() async throws {
        let game = try await fixture.spawnTerminal(in: "/projects/game")
        let view = try XCTUnwrap(shell.terminals.createCustomView(with: game.id))

        shell.terminals.deleteCustomView(view)

        XCTAssertTrue(shell.terminals.customViews.views.isEmpty)
        XCTAssertNotNil(shell.terminals.meta(for: game.id))
    }
}
