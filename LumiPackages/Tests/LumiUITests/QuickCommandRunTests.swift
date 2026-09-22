import Foundation
import XCTest
import LumiKit
import LumiState
import LumiTestSupport
@testable import LumiUI

/// Karar 92: checkout sağ tıkından çalıştırılan hızlı komut.
@MainActor
final class QuickCommandRunTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    func testRunOpensCheckoutAndSpawnsTerminalWithScriptLine() async {
        let command = ProjectQuickCommand(id: "cmd", projectPath: "/projects/game", name: "Open Unity", script: "open \"{path}\"")
        let context = QuickCommandContext(
            path: "/workspaces/game/review", projectPath: "/projects/game", name: "review", branch: "review"
        )
        await shell.runQuickCommand(command, context: context)

        XCTAssertEqual(shell.navigation.activeRepoPath, "/workspaces/game/review")
        let call = fixture.terminalService.spawnCalls.last
        XCTAssertEqual(call?.0, "/workspaces/game/review", "terminal starts in the checkout")
        XCTAssertEqual(call?.1, "Open Unity", "terminal is labelled with the action name")
        XCTAssertEqual(call?.2, "sh '/lumi/quick-commands/cmd-review.sh'")
    }

    func testStartAppRunsInANewTerminalLikeOtherActions() async {
        let command = ProjectQuickCommand(id: "s", projectPath: "/projects/game", name: "Start App", script: "open .", role: .startApp)
        let context = QuickCommandContext(path: "/projects/game", projectPath: "/projects/game", name: "game", branch: "main")
        await shell.runQuickCommand(command, context: context)
        let call = fixture.terminalService.spawnCalls.last
        XCTAssertEqual(call?.0, "/projects/game")
        XCTAssertEqual(call?.1, "Start App")
        XCTAssertEqual(call?.2, "sh '/lumi/quick-commands/s-game.sh'")
    }
}
