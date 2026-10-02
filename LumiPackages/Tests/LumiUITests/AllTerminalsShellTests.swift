import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiUI

/// Karar 103: All Terminals'ın `ShellContext` yüzü — yüzey kapsamı, kart
/// etiketi ve Edit modundan çıkış odağı.
@MainActor
final class AllTerminalsShellTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func setUp() async throws {
        let repos = FakeRepoService()
        await repos.setRepos([
            Repo(name: "Game", path: "/projects/game", isGitRepo: true, source: .projectsRoot),
        ])
        fixture = await ShellContextFixture.make(repo: repos)
        await shell.repos.reload()
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    func testActiveTerminalScopeFollowsTheRoute() {
        XCTAssertNil(shell.activeTerminalScope)

        shell.navigation.openTab("/projects/game")
        XCTAssertEqual(shell.activeTerminalScope, .repo("/projects/game"))

        shell.navigation.setRoute(AllTerminalsRoute.route)
        XCTAssertEqual(shell.activeTerminalScope, .all)
        XCTAssertNil(shell.activeRepoPath, "repo'ya bağlı eylemlerin kapısı kapalı kalır")

        shell.navigation.setRoute(.content(TasksPanelSection.tasks.routeID))
        XCTAssertNil(shell.activeTerminalScope)
    }

    func testCheckoutLabelNamesTheProjectAndItsWorkspace() {
        shell.workspaces.updateRecords([ProjectWorkspace(
            projectPath: "/projects/game", path: "/worktrees/game-feature",
            name: "feature", branch: "feature", scm: .git
        )])

        XCTAssertEqual(shell.checkoutLabel(for: "/projects/game"), "Game")
        XCTAssertEqual(shell.checkoutLabel(for: "/worktrees/game-feature"), "Game / feature")
        XCTAssertEqual(shell.checkoutLabel(for: "/elsewhere/tool"), "tool", "bilinmeyen yol klasör adına düşer")
    }

    func testFinishingArrangementRefocusesTheSurfacesLastActiveCard() async throws {
        let first = try await fixture.spawnTerminal(in: "/projects/game")
        let second = try await fixture.spawnTerminal(in: "/projects/other")
        shell.navigation.setRoute(AllTerminalsRoute.route)
        shell.terminals.focus(first.id)

        shell.toggleArrangingTerminals(in: .all)
        XCTAssertTrue(shell.layout.isArranging(in: .all))
        shell.terminals.focus(nil)

        shell.toggleArrangingTerminals(in: .all)
        XCTAssertFalse(shell.layout.isArranging(in: .all))
        XCTAssertEqual(shell.terminals.activeTerminalID, first.id, "yüzeyin ilk kartı")
        _ = second
    }
}
