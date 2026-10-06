import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// Karar 115: worktree senkronunun saf kuralı ve store/koordinatör akışı.
@MainActor
final class WorkspaceSyncTests: XCTestCase {
    private var root: URL!
    private var project: Repo!
    private var config: FakeConfigService!
    private var discovery: FakeWorktreeDiscovery!
    private var store: ProjectWorkspaceStore!
    private var livePaths = Set<String>()
    private var coordinator: WorkspaceSyncCoordinator!

    override func setUp() async throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: CanonicalPath.of(root.path))
        let projectURL = try makeDirectory("projects/game")
        project = Repo(name: "game", path: projectURL.path, isGitRepo: true, source: .standalone)
        let repoService = FakeRepoService()
        await repoService.setRepos([project])
        let repos = RepoStore(service: repoService)
        await repos.reload()
        config = FakeConfigService()
        discovery = FakeWorktreeDiscovery()
        store = ProjectWorkspaceStore(service: FakeWorkspaceService(), config: config, repos: repos, toasts: ToastStore())
        _ = await store.addProject(project)
        coordinator = WorkspaceSyncCoordinator(discovery: discovery, workspaces: store) { [unowned self] in livePaths }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Saf kural

    func testMissingRecordIsRemovedUnlessATerminalIsLive() {
        let gone = record("gone")
        let kept = record("kept")
        let plan = WorktreeReconciler.plan(
            records: [state(gone, exists: false), state(kept, exists: false)],
            listings: [:], liveCheckoutPaths: [kept.path]
        )
        XCTAssertEqual(plan.removals, [gone.path])
        XCTAssertEqual(plan.missingPaths, [kept.path])
    }

    func testOnlyManagedListableWorktreesAreAdded() {
        let entries = [
            GitWorktreeEntry(path: "/p", branch: "main", isMain: true),
            GitWorktreeEntry(path: "/ws/p/new", branch: "feature", isInsideManagedRoot: true),
            GitWorktreeEntry(path: "/ws/p/stale", branch: "old", isPrunable: true, isInsideManagedRoot: true),
            GitWorktreeEntry(path: "/elsewhere/hotfix", branch: "hotfix"),
        ]
        let plan = WorktreeReconciler.plan(records: [], listings: ["/p": entries], liveCheckoutPaths: [])
        XCTAssertEqual(plan.additions, [
            ProjectWorkspace(projectPath: "/p", path: "/ws/p/new", name: "new", branch: "feature", scm: .git),
        ])
    }

    func testBranchOfKnownWorktreeFollowsGit() {
        let known = record("review")
        let plan = WorktreeReconciler.plan(
            records: [state(known, exists: true)],
            listings: [known.projectPath: [GitWorktreeEntry(path: known.path, branch: "renamed", isInsideManagedRoot: true)]],
            liveCheckoutPaths: []
        )
        XCTAssertEqual(plan.branchUpdates, [known.path: "renamed"])
        XCTAssertTrue(plan.additions.isEmpty)
    }

    func testProtectedAndSidebarPathsAreLeftAlone() {
        let creating = record("creating")
        let plan = WorktreeReconciler.plan(
            records: [state(creating, exists: false)],
            listings: ["/p": [GitWorktreeEntry(path: "/ws/p/also-project", branch: "x", isInsideManagedRoot: true)]],
            liveCheckoutPaths: [],
            protectedPaths: [creating.path],
            sidebarProjectPaths: ["/ws/p/also-project"]
        )
        XCTAssertEqual(plan, WorktreeSyncPlan())
    }

    // MARK: - Koordinatör + store

    func testSyncAddsManagedWorktreeAndHidesExternalOne() async throws {
        let managed = try makeDirectory("workspaces/game/review")
        let external = try makeDirectory("elsewhere/hotfix")
        await discovery.setWorktrees([
            GitWorktreeEntry(path: project.path, branch: "main", isMain: true),
            GitWorktreeEntry(path: managed.path, branch: "review", isInsideManagedRoot: true),
            GitWorktreeEntry(path: external.path, branch: "hotfix"),
        ], for: project.path)

        await coordinator.sync()

        XCTAssertEqual(store.records.map(\.path), [managed.path])
        let saved = await config.config()
        XCTAssertEqual(saved.workspaces.map(\.name), ["review"])
        XCTAssertEqual(store.hiddenWorktrees(for: project.path).map(\.path), [external.path])

        await store.showHiddenWorktrees(for: project.path)
        XCTAssertEqual(Set(store.records.map(\.path)), [managed.path, external.path])
        XCTAssertTrue(store.hiddenWorktrees(for: project.path).isEmpty)
        let shown = try XCTUnwrap(store.records.first { $0.path == external.path })
        XCTAssertTrue(store.isExternal(shown))
        XCTAssertFalse(store.isExternal(try XCTUnwrap(store.records.first { $0.path == managed.path })))

        await store.forgetWorkspace(shown)
        XCTAssertEqual(store.hiddenWorktrees(for: project.path).map(\.path), [external.path])
    }

    func testDeletedWorktreeIsDroppedOnceItsTerminalsAreGone() async throws {
        let folder = try makeDirectory("workspaces/game/old")
        let old = ProjectWorkspace(projectPath: project.path, path: folder.path, name: "old", branch: "old", scm: .git)
        try await config.updateConfig { $0.workspaces = [old] }
        await store.load()
        var dropped: [String] = []
        store.onWorkspacesDropped = { dropped += $0 }
        try FileManager.default.removeItem(at: folder)
        livePaths = [old.path]

        await coordinator.sync()
        XCTAssertEqual(store.records, [old], "A live terminal keeps the row")
        XCTAssertTrue(store.isMissing(old))
        XCTAssertTrue(dropped.isEmpty)

        livePaths = []
        await coordinator.sync()
        XCTAssertTrue(store.records.isEmpty)
        let saved = await config.config()
        XCTAssertTrue(saved.workspaces.isEmpty)
        XCTAssertEqual(dropped, [old.path])
    }

    func testGitFailureNeverDropsOrAddsRows() async throws {
        let folder = try makeDirectory("workspaces/game/keep")
        let keep = ProjectWorkspace(projectPath: project.path, path: folder.path, name: "keep", branch: "keep", scm: .git)
        try await config.updateConfig { $0.workspaces = [keep] }
        await store.load()
        await discovery.setFailure(WorkspaceFailure("git exploded"), for: project.path)

        await coordinator.sync()

        XCTAssertEqual(store.records, [keep])
        XCTAssertTrue(store.worktreeListings.isEmpty)
    }

    func testSyncWatchesGitProjectsAndCheckoutFolders() async throws {
        let folder = try makeDirectory("workspaces/game/w")
        await discovery.setWorktrees([
            GitWorktreeEntry(path: folder.path, branch: "w", isInsideManagedRoot: true),
        ], for: project.path)

        await coordinator.sync()

        let watch = await discovery.watchCalls.last
        XCTAssertEqual(watch?.projects, [project.path])
        XCTAssertEqual(watch?.checkouts, [folder.path])
    }

    func testChangeSignalTriggersSync() async throws {
        let folder = try makeDirectory("workspaces/game/late")
        coordinator.start()
        defer { coordinator.stop() }
        await discovery.setWorktrees([
            GitWorktreeEntry(path: folder.path, branch: "late", isInsideManagedRoot: true),
        ], for: project.path)
        discovery.emitChange()

        let deadline = Date().addingTimeInterval(5)
        while store.records.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.records.map(\.path), [folder.path])
    }

    // MARK: - Yardımcılar

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func record(_ name: String) -> ProjectWorkspace {
        ProjectWorkspace(projectPath: "/p", path: "/ws/p/\(name)", name: name, branch: name, scm: .git)
    }

    private func state(_ record: ProjectWorkspace, exists: Bool) -> WorktreeReconciler.RecordState {
        WorktreeReconciler.RecordState(record: record, canonicalPath: record.path, exists: exists)
    }
}
