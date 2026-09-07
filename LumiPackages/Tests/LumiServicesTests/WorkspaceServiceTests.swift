import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

final class WorkspaceServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumi-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreatesGitWorktreePinnedToHead() async throws {
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try runGit(in: source, "init", "--initial-branch=main")
        try runGit(in: source, "config", "user.email", "test@lumi.local")
        try runGit(in: source, "config", "user.name", "Lumi Test")
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))
        try runGit(in: source, "add", "a.txt")
        try runGit(in: source, "commit", "-m", "initial")

        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let project = Repo(name: "source", path: source.path, isGitRepo: true, source: .standalone)
        let result = try await service.create(WorkspaceCreateRequest(project: project, name: "review", knownProjectPaths: [source.path]))
        XCTAssertEqual(result.workspace.projectPath, source.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.workspace.path + "/a.txt"))
        XCTAssertEqual(try outputGit(in: source, "branch", "--show-current"), "main")
        XCTAssertEqual(try outputGit(in: URL(fileURLWithPath: result.workspace.path), "branch", "--show-current"), "review")
    }

    func testInspectsPlasticWorkspaceFromMachineReadableMetadata() async throws {
        let source = root.appendingPathComponent("plastic").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".plastic"), withIntermediateDirectories: true)
        try "repository \"game@cloud\"\n  br \"/main\"\n".write(to: source.appendingPathComponent(".plastic/plastic.selector"), atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner()
        await runner.stub(commandLine: "/usr/bin/git rev-parse --show-toplevel", with: .failure())
        await runner.stub(commandLine: "/usr/local/bin/cm getworkspacefrompath \(source.path) --format={wkpath}{tab}{type}{tab}{dynamic} --extended", with: .success("\(source.path)\tregular\tfalse\n"))
        await runner.stub(commandLine: "/usr/local/bin/cm status --header --machinereadable --fieldseparator=|", with: .success("STATUS|42|game|cloud\n"))
        let locator = FakeBinaryLocator(paths: ["cm": "/usr/local/bin/cm"])
        let service = WorkspaceService(runner: runner, locator: locator, workspaceRoot: root.appendingPathComponent("workspaces"))
        let project = Repo(name: "plastic", path: source.path, isGitRepo: false, source: .standalone)
        let inspected = try await service.inspect(project: project)
        XCTAssertEqual(inspected.scm, .plastic)
        XCTAssertEqual(inspected.repositorySpec, "game@cloud")
        XCTAssertEqual(inspected.revision, "42")
    }

    func testRejectsDestinationInsideSourceBeforeCreatingBranch() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: source.appendingPathComponent("workspaces"))
        do {
            _ = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "unsafe"))
            XCTFail("Expected source containment rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("outside")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path + "/workspaces"))
        XCTAssertEqual(try outputGit(in: source, "branch", "--list", "unsafe"), "")
    }

    func testRejectsExistingDestinationWithoutChangingIt() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let request = WorkspaceCreateRequest(project: repo(source), name: "review")
        let first = try await service.create(request)
        try Data("keep".utf8).write(to: URL(fileURLWithPath: first.workspace.path + "/untracked"))
        do { _ = try await service.create(request); XCTFail("Expected collision") }
        catch { XCTAssertTrue(error.localizedDescription.contains("already exists")) }
        XCTAssertEqual(try String(contentsOfFile: first.workspace.path + "/untracked", encoding: .utf8), "keep")
    }

    func testSameNamedProjectsGetSeparateDestinationDirectories() async throws {
        let first = try makeGitProject("first")
        let second = try makeGitProject("second")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let a = try await service.create(WorkspaceCreateRequest(project: repo(first, name: "Game"), name: "review"))
        let b = try await service.create(WorkspaceCreateRequest(project: repo(second, name: "Game"), name: "review"))
        XCTAssertNotEqual(a.workspace.path, b.workspace.path)
        XCTAssertTrue(a.workspace.path.hasSuffix("/Game/review"))
        XCTAssertEqual(try outputGit(in: URL(fileURLWithPath: a.workspace.path), "rev-parse", "HEAD"), try outputGit(in: first, "rev-parse", "HEAD"))
    }

    func testSymlinkRedirectUnderOwnedProjectIsRejected() async throws {
        let source = try makeGitProject("source")
        let managed = root.appendingPathComponent("workspaces")
        let service = WorkspaceService(workspaceRoot: managed)
        _ = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "first"))
        let alias = managed.appendingPathComponent("source/escape")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        do {
            _ = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "escape"))
            XCTFail("Expected redirect rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("symbolic-link")) }
        XCTAssertEqual(try outputGit(in: source, "branch", "--list", "escape"), "")
    }

    func testUnbornGitRepositoryFailsBeforeCreatingDestination() async throws {
        let source = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try runGit(in: source, "init", "--initial-branch=main")
        let managed = root.appendingPathComponent("workspaces")
        let service = WorkspaceService(workspaceRoot: managed)
        do { _ = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "review")); XCTFail("Expected missing HEAD") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
    }

    func testInvalidGitBranchDoesNotCreateWorkspace() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        do {
            _ = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "review", branchName: "invalid..branch"))
            XCTFail("Expected branch validation")
        } catch { XCTAssertTrue(error.localizedDescription.contains("check-ref-format")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path + "/workspaces"))
    }

    // MARK: - Silme (karar 49)

    func testRemovesCleanGitWorktreeAndKeepsBranch() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let created = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "review")).workspace
        try await service.remove(created, force: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertFalse(try outputGit(in: source, "worktree", "list").contains(created.path))
        XCTAssertTrue(try outputGit(in: source, "branch", "--list", "review").contains("review"), "branch kullanıcıya kalır")
    }

    func testDirtyGitWorktreeRequiresForce() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let created = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "dirty")).workspace
        try Data("wip".utf8).write(to: URL(fileURLWithPath: created.path).appendingPathComponent("untracked.txt"))
        do {
            try await service.remove(created, force: false)
            XCTFail("Kirli worktree force'suz silinmemeli")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: created.path + "/untracked.txt"), "ilk deneme hiçbir şeyi silmez")
        }
        try await service.remove(created, force: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
    }

    func testRemovePrunesWorktreeWhoseFolderIsAlreadyGone() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let created = try await service.create(WorkspaceCreateRequest(project: repo(source), name: "gone")).workspace
        try FileManager.default.removeItem(atPath: created.path)
        try await service.remove(created, force: false)
        XCTAssertFalse(try outputGit(in: source, "worktree", "list").contains("gone"))
    }

    func testRemoveRefusesPathsOutsideManagedRoot() async throws {
        let source = try makeGitProject("source")
        let service = WorkspaceService(workspaceRoot: root.appendingPathComponent("workspaces"))
        let outside = ProjectWorkspace(projectPath: source.path, path: source.path, name: "source", branch: "main", scm: .git)
        do {
            try await service.remove(outside, force: true)
            XCTFail("Yönetilen kök dışı yol silinmemeli")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path + "/a.txt"))
        }
        let rootItself = ProjectWorkspace(projectPath: source.path, path: root.appendingPathComponent("workspaces").path, name: "root", branch: "main", scm: .none)
        do {
            try await service.remove(rootItself, force: true)
            XCTFail("Yönetilen kökün kendisi silinmemeli")
        } catch {}
    }

    func testRemovePlasticWithoutCLIOnlyForceTrashesFolder() async throws {
        let workspaces = root.appendingPathComponent("workspaces")
        let folder = workspaces.appendingPathComponent("game/ui")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let runner = FakeProcessRunner()
        let service = WorkspaceService(runner: runner, locator: FakeBinaryLocator(paths: [:]), workspaceRoot: workspaces)
        let record = ProjectWorkspace(projectPath: root.appendingPathComponent("plastic").path, path: folder.path, name: "ui", branch: "/main/ui", scm: .plastic)
        do {
            try await service.remove(record, force: false)
            XCTFail("cm yokken force'suz silme reddedilmeli")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        }
        try await service.remove(record, force: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    private func repo(_ url: URL, name: String = "source") -> Repo {
        Repo(name: name, path: url.path, isGitRepo: true, source: .standalone)
    }

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

    private func outputGit(in directory: URL, _ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
