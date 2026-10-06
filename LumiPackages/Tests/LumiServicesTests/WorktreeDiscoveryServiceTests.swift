import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// Karar 115: `git worktree list --porcelain` ayrıştırması, keşif ve izleme.
final class WorktreeDiscoveryServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-worktrees-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Ayrıştırıcı

    func testParsesNulSeparatedPorcelain() {
        let output = [
            "worktree /repo", "HEAD abc", "branch refs/heads/main", "",
            "worktree /ws/feature", "HEAD def", "branch refs/heads/feature/x", "locked reason here", "",
            "worktree /ws/detached", "HEAD 123", "detached", "prunable gitdir file points to non-existent location", "",
        ].joined(separator: "\0") + "\0"
        let entries = GitWorktreeListParser.parse(output, nulSeparated: true)
        XCTAssertEqual(entries, [
            .init(path: "/repo", branch: "main"),
            .init(path: "/ws/feature", branch: "feature/x", isLocked: true),
            .init(path: "/ws/detached", branch: nil, isPrunable: true),
        ])
    }

    func testParsesNewlinePorcelainWithBareEntry() {
        let output = "worktree /repo.git\nbare\n\nworktree /ws/a\nHEAD 1\nbranch refs/heads/a\n"
        let entries = GitWorktreeListParser.parse(output, nulSeparated: false)
        XCTAssertEqual(entries, [
            .init(path: "/repo.git", branch: nil, isBare: true),
            .init(path: "/ws/a", branch: "a"),
        ])
    }

    func testKeepsSpacesInPaths() {
        let entries = GitWorktreeListParser.parse("worktree /my repo/a b\0branch refs/heads/x\0\0", nulSeparated: true)
        XCTAssertEqual(entries.map(\.path), ["/my repo/a b"])
    }

    // MARK: - Gerçek git

    func testListsMainManagedAndExternalWorktrees() async throws {
        let project = try makeGitProject("source")
        let managedRoot = root.appendingPathComponent("workspaces")
        let managed = managedRoot.appendingPathComponent("source/review")
        let external = root.appendingPathComponent("elsewhere/hotfix")
        try runGit(in: project, "worktree", "add", "-b", "review", managed.path)
        try runGit(in: project, "worktree", "add", "--detach", external.path)

        let service = WorktreeDiscoveryService(managedRoot: managedRoot)
        let entries = try await service.worktrees(projectPath: project.path)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].path, project.path)
        XCTAssertTrue(entries[0].isMain)
        XCTAssertFalse(entries[0].isListable)
        let review = try XCTUnwrap(entries.first { $0.path == managed.path })
        XCTAssertEqual(review.branch, "review")
        XCTAssertTrue(review.isInsideManagedRoot)
        XCTAssertTrue(review.isListable)
        let hotfix = try XCTUnwrap(entries.first { $0.path == external.path })
        XCTAssertNil(hotfix.branch)
        XCTAssertFalse(hotfix.isInsideManagedRoot)
    }

    func testFolderDeletedWithoutGitIsPrunable() async throws {
        let project = try makeGitProject("source")
        let worktree = root.appendingPathComponent("workspaces/source/gone")
        try runGit(in: project, "worktree", "add", "-b", "gone", worktree.path)
        try FileManager.default.removeItem(at: worktree)

        let service = WorktreeDiscoveryService(managedRoot: root.appendingPathComponent("workspaces"))
        let gone = try await service.worktrees(projectPath: project.path).first { $0.path == worktree.path }

        XCTAssertEqual(gone?.isPrunable, true)
        XCTAssertEqual(gone?.isListable, false)
    }

    func testGitFailureThrowsInsteadOfReturningEmptyList() async throws {
        let plain = root.appendingPathComponent("not-a-repo")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        let service = WorktreeDiscoveryService(managedRoot: root)
        do {
            _ = try await service.worktrees(projectPath: plain.path)
            XCTFail("expected a failure")
        } catch {}
    }

    func testFallsBackToNewlineFormatWhenNulFlagIsRejected() async throws {
        let runner = FakeProcessRunner()
        let project = root.appendingPathComponent("p")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        await runner.stub(commandLine: "/usr/bin/git worktree list --porcelain -z", with: .failure())
        await runner.stub(
            commandLine: "/usr/bin/git worktree list --porcelain",
            with: .success("worktree \(project.path)\nbranch refs/heads/main\n")
        )
        let service = WorktreeDiscoveryService(runner: runner, managedRoot: root)
        let entries = try await service.worktrees(projectPath: project.path)
        XCTAssertEqual(entries.map(\.branch), ["main"])
    }

    func testWatcherSignalsWorktreeAddedFromOutside() async throws {
        let project = try makeGitProject("source")
        let service = WorktreeDiscoveryService(managedRoot: root, debounce: 0.05)
        let changes = service.changes()
        await service.watch(projectPaths: [project.path], checkoutPaths: [])

        let signalled = expectation(description: "change")
        let listener = Task {
            for await _ in changes { signalled.fulfill(); return }
        }
        try runGit(in: project, "worktree", "add", "-b", "outside", root.appendingPathComponent("outside").path)
        await fulfillment(of: [signalled], timeout: 5)
        listener.cancel()
    }

    func testWatcherSignalsCheckoutFolderDeleted() async throws {
        let parent = root.appendingPathComponent("workspaces/source")
        let checkout = parent.appendingPathComponent("ws")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        let service = WorktreeDiscoveryService(managedRoot: root, debounce: 0.05)
        let changes = service.changes()
        await service.watch(projectPaths: [], checkoutPaths: [checkout.path])

        let signalled = expectation(description: "change")
        let listener = Task {
            for await _ in changes { signalled.fulfill(); return }
        }
        try FileManager.default.removeItem(at: checkout)
        await fulfillment(of: [signalled], timeout: 5)
        listener.cancel()
    }

    // MARK: - Yardımcılar

    private func makeGitProject(_ name: String) throws -> URL {
        let source = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try runGit(in: source, "init", "--initial-branch=main")
        try runGit(in: source, "config", "user.email", "test@lumi.local")
        try runGit(in: source, "config", "user.name", "Lumi Test")
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))
        try runGit(in: source, "add", "a.txt")
        try runGit(in: source, "commit", "-m", "initial")
        return source
    }

    private func runGit(in directory: URL, _ args: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, args.joined(separator: " "))
    }
}
