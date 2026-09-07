import Foundation
import XCTest
import LumiKit
@testable import LumiState

/// `DialogRouter` birim testleri — beş bağımsız bayrağın yerini alan tek
/// sum type (refactor 5.2).
@MainActor
final class DialogRouterTests: XCTestCase {
    private var router: DialogRouter!

    override func setUp() async throws {
        router = DialogRouter()
    }

    func testStartsWithNoDialog() {
        XCTAssertEqual(router.active, .none)
        XCTAssertFalse(router.isInputBlockingOverlayOpen)
        XCTAssertNil(router.closeTabDialog)
        XCTAssertNil(router.quitDialogTerminalCount)
    }

    func testPresentingReplacesPreviousDialog() {
        router.present(.repoSelector)
        router.present(.settings)
        XCTAssertEqual(router.active, .settings, "aynı anda tek modal — geçersiz durum temsil edilemez")
        XCTAssertFalse(router.isPresenting(.repoSelector))
    }

    func testDismissOfAnotherDialogIsIgnored() {
        router.present(.settings)
        router.dismiss(.repoSelector)
        XCTAssertEqual(router.active, .settings, "bayrak adaptörü başka modalı kapatamaz")
        router.dismiss(.settings)
        XCTAssertEqual(router.active, .none)
    }

    func testEveryDialogBlocksTerminalInput() {
        let dialogs: [ActiveDialog] = [
            .repoSelector,
            .sidebarProjectSelector,
            .createWorkspace(projectPath: "/r"),
            .settings,
            .onboarding,
            .closeTab(CloseTabDialogState(repoPath: "/r", repoName: "r", minimizedCount: 1)),
            .deleteWorkspace(DeleteWorkspaceDialogState(
                workspace: ProjectWorkspace(projectPath: "/r", path: "/w", name: "w", branch: "w", scm: .git), sessionCount: 1)),
            .quit(terminalCount: 2),
        ]
        for dialog in dialogs {
            router.present(dialog)
            XCTAssertTrue(router.isInputBlockingOverlayOpen, "\(dialog) terminal girdisini bloklamalı")
            XCTAssertTrue(router.active.isPresented)
        }
        router.dismiss()
        XCTAssertFalse(router.isInputBlockingOverlayOpen)
    }

    func testCloseTabProjectionIsStructural() {
        let state = CloseTabDialogState(repoPath: "/r/alpha", repoName: "alpha", minimizedCount: 3)
        router.present(.closeTab(state))
        XCTAssertEqual(router.closeTabDialog, state)
        XCTAssertNil(router.quitDialogTerminalCount, "diğer projeksiyon otomatik nil")
    }

    func testQuitResolutionClearsDialogAndReportsDecision() {
        var decisions: [Bool] = []
        router.onQuitResolved = { decisions.append($0) }

        router.presentQuitDialog(terminalCount: 3)
        XCTAssertEqual(router.quitDialogTerminalCount, 3)
        XCTAssertTrue(decisions.isEmpty, "dialog açılırken karar bildirilmez")

        router.resolveQuit(true)
        XCTAssertNil(router.quitDialogTerminalCount)
        XCTAssertEqual(decisions, [true])
    }

    func testQuitResolutionDoesNotDismissAnotherDialog() {
        router.present(.settings)
        var decisions: [Bool] = []
        router.onQuitResolved = { decisions.append($0) }

        router.resolveQuit(false)

        XCTAssertEqual(router.active, .settings)
        XCTAssertEqual(decisions, [false], "karar yine bildirilir (.terminateLater cevapsız kalmaz)")
    }

    func testCollapsedRepoGroupsSurviveDialogChanges() {
        router.present(.repoSelector)
        router.collapsedRepoGroups = ["__standalone__"]
        router.dismiss()
        XCTAssertEqual(router.collapsedRepoGroups, ["__standalone__"], "session-local, dialoga bağlı değil")
    }
}
