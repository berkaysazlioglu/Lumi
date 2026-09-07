import Foundation
import LumiKit
import LumiState
import LumiTestSupport
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

    func testSidebarSelectionDoesNotOpenTopbarTabOrAlterDiscoveryPaths() async throws {
        fixture.stop()
        let service = FakeRepoService()
        let repo = Repo(name: "Game", path: "/projects/game", isGitRepo: true, source: .projectsRoot)
        await service.setRepos([repo])
        fixture = await ShellContextFixture.make(repo: service)
        await shell.repos.reload()
        shell.navigation.openTab(repo.path)
        shell.navigation.openTab("/already-open")
        shell.dialogs.present(.sidebarProjectSelector)
        await shell.addSidebarProject(repo)
        XCTAssertEqual(shell.dialogs.active, .none)
        XCTAssertEqual(shell.workspaces.addedProjects, [repo])
        XCTAssertEqual(shell.navigation.openTabs, [repo.path, "/already-open"])
        XCTAssertEqual(shell.navigation.activeRepoPath, "/already-open")
        let saved = await fixture.config.config()
        XCTAssertEqual(saved.sidebarProjectPaths, [repo.path])
        XCTAssertTrue(saved.additionalPaths.isEmpty)
        shell.navigation.openTab(repo.path)
        await shell.workspaces.removeProject(repo)
        XCTAssertTrue(shell.navigation.openTabs.contains(repo.path), "Removing from sidebar does not close a topbar tab")
    }

    func testWorkspaceCreationDismissesModalAndDoesNotInterruptLaterNavigation() async throws {
        fixture.stop()
        let service = FakeWorkspaceService()
        let repoService = FakeRepoService()
        let project = Repo(name: "Game", path: "/p", isGitRepo: false, source: .standalone)
        let result = ProjectWorkspace(projectPath: "/p", path: "/w/review", name: "Review", branch: "/main", scm: .plastic)
        await repoService.setRepos([project])
        await service.setDefaultInspection(.success(WorkspaceSource(projectPath: "/p", scm: .plastic, branch: "/main", destinationDirectory: "/w")))
        await service.setCreateOutcome(.success(WorkspaceCreateResult(workspace: result)))
        await service.setCreateDelay(.milliseconds(80))
        fixture = await ShellContextFixture.make(repo: repoService, workspaces: service)
        await shell.repos.reload()
        await shell.workspaces.selectProject(project)
        shell.workspaces.name = "Review"
        shell.dialogs.present(.createWorkspace(projectPath: project.path))
        shell.startWorkspaceCreation()
        XCTAssertEqual(shell.dialogs.active, .none)
        XCTAssertTrue(shell.workspaces.isCreating)
        XCTAssertFalse(shell.dialogs.isInputBlockingOverlayOpen)
        shell.navigation.openTab("/another-project")
        shell.dialogs.present(.settings)
        let deadline = Date().addingTimeInterval(2)
        while shell.workspaces.isCreating, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(shell.workspaces.lastCreated, result)
        XCTAssertEqual(shell.navigation.activeRepoPath, "/another-project")
        XCTAssertEqual(shell.dialogs.active, .settings)
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
            workspaces: context.workspaces,
            git: context.git,
            agentHistory: context.agentHistory,
            fileViewer: context.fileViewer,
            settings: context.settings,
            sessionSchedule: context.sessionSchedule,
            promptQueue: context.promptQueue,
            toasts: context.toasts,
            onboarding: context.onboarding,
            usage: context.usage,
            computerAwake: context.computerAwake,
            resourceUsage: context.resourceUsage,
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
