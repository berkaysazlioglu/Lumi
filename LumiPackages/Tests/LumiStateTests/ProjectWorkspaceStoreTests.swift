import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class ProjectWorkspaceStoreTests: XCTestCase {
    private let project = Repo(name: "Game", path: "/projects/game", isGitRepo: true, source: .standalone)
    private let record = ProjectWorkspace(projectPath: "/projects/game", path: "/workspaces/game/review", name: "Review", branch: "review", scm: .git)
    private var service: FakeWorkspaceService!
    private var config: FakeConfigService!
    private var repoService: FakeRepoService!
    private var repos: RepoStore!
    private var store: ProjectWorkspaceStore!

    override func setUp() async throws {
        service = FakeWorkspaceService()
        config = FakeConfigService()
        repoService = FakeRepoService()
        await repoService.setRepos([project])
        repos = RepoStore(service: repoService)
        await repos.reload()
        store = ProjectWorkspaceStore(service: service, config: config, repos: repos, toasts: ToastStore())
        await service.setDefaultInspection(.success(WorkspaceSource(projectPath: project.path, scm: .git, branch: "main", revision: "abc", destinationDirectory: "/workspaces/game", isUnityProject: true, hasLibrary: true)))
        await service.setCreateOutcome(.success(WorkspaceCreateResult(workspace: record)))
    }

    func testSidebarSelectionIsIndependentOfAdditionalPaths() async throws {
        let discovered = Repo(name: "Discovered", path: "/projects/discovered", isGitRepo: true, source: .projectsRoot)
        await repoService.setRepos([project, discovered])
        await repos.reload()
        let roots = [AdditionalPath(id: "root", path: "/projects", type: .root),
                     AdditionalPath(id: "repo", path: project.path, type: .repo)]
        repos.setAdditionalPaths(roots)
        try await config.updateConfig { $0.additionalPaths = roots }
        await store.load()
        XCTAssertTrue(store.addedProjects.isEmpty, "Neither roots nor explicit additional paths select sidebar projects")
        let added = await store.addProject(discovered)
        XCTAssertTrue(added)
        XCTAssertEqual(store.addedProjects, [discovered])
        let saved = await config.config()
        XCTAssertEqual(saved.additionalPaths, roots)
        XCTAssertEqual(saved.sidebarProjectPaths, [discovered.path])
        store.updateRecords([record])
        XCTAssertEqual(store.addedProjects, [discovered])
    }

    func testSidebarSelectionPersistsDeduplicatesAndRemovesWithoutDeletingWorkspaces() async {
        _ = await store.addProject(project)
        _ = await store.addProject(project)
        let saved = await config.config()
        XCTAssertEqual(saved.sidebarProjectPaths, [project.path])
        store.updateSidebarProjects([])
        await store.load()
        XCTAssertEqual(store.addedProjects, [project])
        store.updateRecords([record])
        await store.removeProject(project)
        XCTAssertTrue(store.addedProjects.isEmpty)
        XCTAssertEqual(store.records, [record])
        XCTAssertEqual(repos.repo(at: project.path), project)
        let updated = await config.config()
        XCTAssertTrue(updated.sidebarProjectPaths.isEmpty)
    }

    func testSidebarSaveFailureDoesNotChangeSelection() async {
        await config.setUpdateConfigError(.configIOFailed(file: "config", detail: "disk full"))
        let added = await store.addProject(project)
        XCTAssertFalse(added)
        XCTAssertTrue(store.addedProjects.isEmpty)
    }

    func testPlasticDefaultsToCurrentBranchAndGitResetsToNewBranch() async {
        await service.setDefaultInspection(.success(WorkspaceSource(projectPath: project.path, scm: .plastic,
            branch: "/main/release", destinationDirectory: "/w", isUnityProject: true)))
        await store.selectProject(project)
        XCTAssertFalse(store.createNewBranch)
        store.name = "Review"
        _ = await store.create(projects: [project])
        let calls = await service.createCalls
        XCTAssertEqual(calls.first?.request.createNewBranch, false)
        store.clearForm()
        await service.setDefaultInspection(.success(WorkspaceSource(projectPath: project.path, scm: .git, destinationDirectory: "/w")))
        await store.selectProject(project)
        XCTAssertTrue(store.createNewBranch)
    }

    func testBackgroundCreationLocksSynchronouslyAndFinishesWithoutModalLifetime() async throws {
        await service.setCreateDelay(.milliseconds(80))
        await store.selectProject(project)
        store.name = "Review"
        XCTAssertTrue(store.startCreation(projects: [project]))
        XCTAssertTrue(store.isCreating)
        XCTAssertTrue(store.hasBackgroundOperation)
        XCTAssertFalse(store.startCreation(projects: [project]))
        let deadline = Date().addingTimeInterval(2)
        while store.isCreating, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(store.isCreating)
        XCTAssertEqual(store.lastCreated, record)
        XCTAssertEqual(store.records, [record])
        XCTAssertTrue(store.hasBackgroundOperation, "The sidebar keeps the ready result available")
    }

    func testCreationPersistsWithoutLosingConfigAndSurvivesReload() async throws {
        try await config.updateConfig { $0.theme = "light" }
        await store.selectProject(project)
        store.name = "Review"
        store.copyLibrary = true
        let created = await store.create(projects: [project])
        XCTAssertEqual(created, record)
        let saved = await config.config()
        XCTAssertEqual(saved.workspaces, [record])
        XCTAssertEqual(saved.theme, "light")
        XCTAssertNil(store.warningMessage)
        XCTAssertFalse(store.canCreate)
        await repos.reload()
        XCTAssertEqual(repos.repo(at: record.path), record.repo)
        await store.load()
        XCTAssertEqual(store.workspaces(for: project.path), [record])
        let calls = await service.createCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls.first?.request.branchName)
        XCTAssertEqual(calls.first?.request.copyLibrary, true)
    }

    func testSaveFailureCanRetryWithoutRecreatingWorkspace() async {
        await config.setUpdateConfigError(.configIOFailed(file: "config", detail: "disk full"))
        await store.selectProject(project)
        store.name = "Review"
        _ = await store.create(projects: [project])
        XCTAssertTrue(store.needsSave)
        XCTAssertTrue(store.warningMessage?.contains(record.path) == true)
        store.updateRecords([])
        XCTAssertEqual(store.records, [record], "A config event cannot erase the unsaved workspace")
        await config.setUpdateConfigError(nil)
        let saved = await store.retrySave()
        XCTAssertTrue(saved)
        XCTAssertFalse(store.needsSave)
        XCTAssertNil(store.warningMessage)
        let calls = await service.createCalls
        XCTAssertEqual(calls.count, 1)
    }

    func testLibraryFailureRetainsWorkspaceAndRetryDoesNotCreateAgain() async {
        await service.setCreateOutcome(.success(WorkspaceCreateResult(workspace: record, warning: "Library copy failed")))
        await store.selectProject(project)
        store.name = "Review"
        _ = await store.create(projects: [project])
        XCTAssertEqual(store.lastCreated, record)
        XCTAssertTrue(store.libraryNeedsRetry)
        XCTAssertFalse(store.needsSave)
        await store.retryLibrary()
        XCTAssertFalse(store.libraryNeedsRetry)
        XCTAssertNil(store.warningMessage)
        XCTAssertEqual(store.lastCreated, record, "Continue must remain available after retry succeeds")
        let calls = await service.createCalls
        let copies = await service.copyCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(copies.first?.0, project.path)
        XCTAssertEqual(copies.first?.1, record.path)
    }

    func testSecondClickAndDismissAreBlockedWhileCreating() async throws {
        await service.setCreateDelay(.milliseconds(100))
        await store.selectProject(project)
        store.name = "Review"
        let task = Task { await store.create(projects: [project]) }
        while !store.isCreating { await Task.yield() }
        let duplicate = await store.create(projects: [project])
        store.clearForm()
        XCTAssertNil(duplicate)
        XCTAssertEqual(store.selectedProjectPath, project.path)
        _ = await task.value
        XCTAssertFalse(store.isCreating)
        let calls = await service.createCalls
        XCTAssertEqual(calls.count, 1)
    }

    func testDismissedInspectionCannotRepopulateForm() async {
        await service.setInspectionDelay(.milliseconds(50))
        let task = Task { await store.selectProject(project) }
        while !store.isInspecting { await Task.yield() }
        store.clearForm()
        await task.value
        XCTAssertNil(store.source)
        XCTAssertNil(store.selectedProjectPath)
        XCTAssertFalse(store.isInspecting)
    }

    func testFailedCreationDoesNotRegisterWorkspaceAndAllowsRetry() async {
        await service.setCreateOutcome(.failure(WorkspaceFailure("Branch exists")))
        await store.selectProject(project)
        store.name = "Review"
        _ = await store.create(projects: [project])
        XCTAssertEqual(store.errorMessage, "Branch exists")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(store.lastCreated)
        XCTAssertTrue(store.canCreate)
    }

    func testUnsupportedProjectAndInvalidNameDisableCreation() async {
        await store.selectProject(project)
        store.name = "../___"
        XCTAssertFalse(store.canCreate)
        store.name = "Fix navigation"
        XCTAssertEqual(store.destinationPath, "/workspaces/game/Fix-navigation")
        XCTAssertTrue(store.canCreate)
        await service.setDefaultInspection(.success(WorkspaceSource(projectPath: project.path, scm: .none, destinationDirectory: "/w")))
        await store.selectProject(project)
        store.name = "Review"
        XCTAssertFalse(store.canCreate)
    }

    func testClearingRecoveryFormDoesNotLosePendingRecord() async {
        await config.setUpdateConfigError(.configIOFailed(file: "config", detail: "disk full"))
        await store.selectProject(project)
        store.name = "Review"
        _ = await store.create(projects: [project])
        store.clearForm()
        store.updateRecords([])
        XCTAssertEqual(store.records, [record])
        XCTAssertEqual(repos.repo(at: record.path), record.repo)
    }
}
