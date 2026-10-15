import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiUI

/// Karar 118: `Restart to Update` onayının kabuk köprüleri.
@MainActor
final class InstallUpdateDialogTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    func testRequestWithoutStagedUpdateIsANoOp() {
        shell.requestInstallUpdate()
        XCTAssertEqual(shell.dialogs.active, .none)
    }

    func testDialogCarriesLiveTerminalCountAndBlocksInput() async throws {
        await shell.appUpdate.check()
        _ = try await fixture.spawnTerminal(named: "a")
        _ = try await fixture.spawnTerminal(named: "b")
        shell.requestInstallUpdate()
        XCTAssertEqual(
            shell.dialogs.installUpdateDialog,
            InstallUpdateDialogState(version: "0.9.0", terminalCount: 2, isScheduledOnQuit: false)
        )
        XCTAssertTrue(shell.dialogs.isInputBlockingOverlayOpen)
    }

    func testInstallOnQuitThenUndo() async {
        await shell.appUpdate.check()
        shell.requestInstallUpdate()
        shell.resolveInstallUpdate(.toggleInstallOnQuit)
        XCTAssertEqual(shell.dialogs.active, .none)
        XCTAssertEqual(shell.appUpdate.installTiming, .onQuit)

        shell.requestInstallUpdate()
        XCTAssertEqual(shell.dialogs.installUpdateDialog?.isScheduledOnQuit, true)
        shell.resolveInstallUpdate(.toggleInstallOnQuit)
        XCTAssertNil(shell.appUpdate.installTiming)
    }

    func testCancelChangesNothing() async {
        await shell.appUpdate.check()
        shell.requestInstallUpdate()
        shell.resolveInstallUpdate(.cancel)
        XCTAssertEqual(shell.dialogs.active, .none)
        XCTAssertNil(shell.appUpdate.installTiming)
        // Dialog kapandıktan sonra gelen ikinci çözüm (binding set'i) no-op'tur.
        shell.resolveInstallUpdate(.restartNow)
        XCTAssertNil(shell.appUpdate.installTiming)
    }

    func testRestartNowRequestsQuit() async {
        await shell.appUpdate.check()
        var restartRequests = 0
        shell.appUpdate.onRestartRequested = { restartRequests += 1 }
        shell.requestInstallUpdate()
        shell.resolveInstallUpdate(.restartNow)
        XCTAssertEqual(shell.dialogs.active, .none)
        // Kayıt asenkron: kapanış ancak kurulum kaydedildikten sonra istenir.
        for _ in 0 ..< 100 where restartRequests == 0 {
            await Task.yield()
        }
        XCTAssertEqual(restartRequests, 1)
        XCTAssertEqual(shell.appUpdate.installTiming, .restartNow)
    }

    func testMessageWarnsAboutTerminalsOnlyWhenThereAreSome() {
        let none = InstallUpdateDialogOverlay.message(terminalCount: 0)
        XCTAssertFalse(none.contains("terminal"))
        XCTAssertTrue(InstallUpdateDialogOverlay.message(terminalCount: 1).contains("Your 1 open terminal will be closed"))
        XCTAssertTrue(InstallUpdateDialogOverlay.message(terminalCount: 3).contains("Your 3 open terminals will be closed"))
    }

    func testQuitMessageNamesTerminalCount() {
        XCTAssertTrue(QuitDialogOverlay.message(terminalCount: 1).hasPrefix("Your 1 open terminal will be closed"))
        XCTAssertTrue(QuitDialogOverlay.message(terminalCount: 4).hasPrefix("Your 4 open terminals will be closed"))
    }

    func testQuitPreconfirmationIsConsumedOnce() {
        shell.dialogs.preconfirmQuit()
        XCTAssertTrue(shell.dialogs.consumeQuitPreconfirmation())
        XCTAssertFalse(shell.dialogs.consumeQuitPreconfirmation())
    }
}
