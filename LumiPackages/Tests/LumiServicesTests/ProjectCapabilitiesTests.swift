import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

final class ProjectCapabilitiesTests: XCTestCase {
    func testUnityRequiresAssetsAndProjectVersionAndGitDoesNotRequireCommits() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("true\n"))
        let service = RepoService(runner: runner)
        let assetsOnly = await service.capabilities(repoPath: root.path)
        XCTAssertTrue(assetsOnly.isGitRepo)
        XCTAssertFalse(assetsOnly.isUnityProject)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ProjectSettings"), withIntermediateDirectories: true)
        try Data("m_EditorVersion: 6000.0.72f1".utf8).write(to: root.appendingPathComponent("ProjectSettings/ProjectVersion.txt"))
        let unity = await service.capabilities(repoPath: root.path)
        XCTAssertTrue(unity.isUnityProject)
        await runner.setDefaultResult(.failure(exitCode: 128))
        let folder = await service.capabilities(repoPath: root.path)
        XCTAssertFalse(folder.isGitRepo)
        XCTAssertTrue(folder.isUnityProject)
        let commands = await runner.commandLines
        XCTAssertEqual(Set(commands), ["/usr/bin/git rev-parse --is-inside-work-tree"])
    }

    func testPlasticWorkspaceIsDetectedByDotPlasticDirectoryWithoutSpawningCM() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 128))
        let service = RepoService(runner: runner)

        let folder = await service.capabilities(repoPath: root.path)
        XCTAssertFalse(folder.isPlasticWorkspace)
        XCTAssertFalse(folder.hasSourceControl)

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".plastic"), withIntermediateDirectories: true)
        let plastic = await service.capabilities(repoPath: root.path)
        XCTAssertTrue(plastic.isPlasticWorkspace)
        XCTAssertFalse(plastic.isGitRepo)
        XCTAssertTrue(plastic.hasSourceControl)

        let executables = await runner.invocations.map(\.executable)
        XCTAssertEqual(Set(executables), ["/usr/bin/git"])
    }
}
