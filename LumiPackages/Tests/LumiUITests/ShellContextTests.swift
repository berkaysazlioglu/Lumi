import Foundation
import LumiKit
import LumiState
import SwiftUI
import XCTest
@testable import LumiUI

/// `ShellContext`'in koordinasyon intent'leri (Faz 6.1) — eski
/// `WorkspaceStore` facade'ının cross-store davranışları buraya taşındı,
/// **assertion'lar aynı**.
@MainActor
final class ShellContextTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    // MARK: - Close-tab guard'ı (navigation sorar, dialogs sunar)

    func testCloseTabWithoutMinimizedTerminalsClosesImmediately() {
        shell.navigation.openTab("/r/alpha")
        shell.requestCloseTab("/r/alpha", repoName: "alpha")

        XCTAssertNil(shell.dialogs.closeTabDialog, "minimize yoksa dialog açılmaz")
        XCTAssertTrue(shell.navigation.openTabs.isEmpty)
    }

    func testCloseTabGuardedByMinimizedTerminals() async throws {
        shell.navigation.openTab("/r/alpha")
        let meta = try await fixture.spawnTerminal()
        shell.terminals.minimize(meta.id)

        shell.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertEqual(shell.dialogs.closeTabDialog?.minimizedCount, 1, "guard dialog açılmalı")
        XCTAssertEqual(shell.dialogs.closeTabDialog?.repoName, "alpha")
        XCTAssertEqual(shell.navigation.openTabs, ["/r/alpha"], "tab henüz kapanmamalı")
        XCTAssertTrue(fixture.terminalService.killedIDs.isEmpty)

        shell.confirmCloseTab()
        XCTAssertNil(shell.dialogs.closeTabDialog)
        XCTAssertTrue(shell.navigation.openTabs.isEmpty)
        XCTAssertEqual(fixture.terminalService.killedIDs, [meta.id])
    }

    func testCancelCloseTabKeepsEverything() async throws {
        shell.navigation.openTab("/r/alpha")
        let meta = try await fixture.spawnTerminal()
        shell.terminals.minimize(meta.id)

        shell.requestCloseTab("/r/alpha", repoName: "alpha")
        shell.cancelCloseTab()

        XCTAssertNil(shell.dialogs.closeTabDialog)
        XCTAssertEqual(shell.navigation.openTabs, ["/r/alpha"])
        XCTAssertTrue(fixture.terminalService.killedIDs.isEmpty)
    }

    func testCancelWithoutAnOpenDialogIsANoOp() {
        shell.dialogs.present(.settings)
        shell.cancelCloseTab()
        XCTAssertTrue(shell.dialogs.isSettingsOpen, "başka bir modal kazara kapanmaz")
    }

    func testConfirmWithoutAnOpenDialogIsANoOp() {
        shell.navigation.openTab("/r/alpha")
        shell.confirmCloseTab()
        XCTAssertEqual(shell.navigation.openTabs, ["/r/alpha"])
    }

    // MARK: - Türevler

    func testActiveRepoPathProjectsTheRepoRouteOnly() {
        XCTAssertNil(shell.activeRepoPath)
        shell.navigation.openTab("/r/alpha")
        XCTAssertEqual(shell.activeRepoPath, "/r/alpha")
        shell.navigation.setRoute(.content(ContentRouteID("placeholder")))
        XCTAssertNil(shell.activeRepoPath, "repo-dışı route panel öğelerini kapatır")
    }

    // MARK: - FileViewer sunumları (parent closure'ı yerine bağlam)

    func testPresentationsAreIgnoredWithoutAnActiveRepo() async {
        shell.presentFile("README.md")
        shell.presentDiff("README.md")
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(shell.fileViewer.isPresented, "repo yokken sunum yapılmaz")
    }

    func testPresentFileOpensTheViewerForTheActiveRepo() async throws {
        shell.navigation.openTab("/r/alpha")
        shell.presentFile("README.md")

        let deadline = Date().addingTimeInterval(2)
        while !shell.fileViewer.isPresented, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(shell.fileViewer.isPresented)
    }

    // MARK: - Reveal / trash (servis-yüzlü aksiyonlar)

    func testRevealAndTrashCarryTheActiveRepoPath() {
        var revealed: [String] = []
        var trashed: [String] = []
        let context = shell
        let probe = ShellContext(
            navigation: context.navigation,
            layout: context.layout,
            dialogs: context.dialogs,
            terminals: context.terminals,
            repos: context.repos,
            git: context.git,
            fileViewer: context.fileViewer,
            settings: context.settings,
            sessionSchedule: context.sessionSchedule,
            promptQueue: context.promptQueue,
            toasts: context.toasts,
            onboarding: context.onboarding,
            usage: context.usage,
            viewProvider: context.viewProvider,
            highlighter: context.highlighter,
            actions: ShellActions(
                chooseFolder: { nil },
                reveal: { repo, path in revealed.append(repo + "|" + path) },
                trash: { repo, path in trashed.append(repo + "|" + path) }
            )
        )

        probe.reveal("Sources/main.swift")
        XCTAssertTrue(revealed.isEmpty, "repo yokken aksiyon çalışmaz")

        probe.navigation.openTab("/r/alpha")
        probe.reveal("Sources/main.swift")
        probe.trash("Sources/old.swift")
        XCTAssertEqual(revealed, ["/r/alpha|Sources/main.swift"])
        XCTAssertEqual(trashed, ["/r/alpha|Sources/old.swift"])
    }
}
