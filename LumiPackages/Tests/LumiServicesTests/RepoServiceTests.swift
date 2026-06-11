import Foundation
import XCTest
import LumiKit
@testable import LumiServices

final class RepoServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func makeDir(_ components: String...) throws -> String {
        let url = components.reduce(tempRoot!) { $0.appendingPathComponent($1) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    func testDiscoveryRules() async throws {
        // .git dizinli repo
        _ = try makeDir("projects", "repoA", ".git")
        // .git DOSYALI repo (submodule/worktree biçimi de git sayılır — spec/12)
        let repoB = try makeDir("projects", "repoB")
        FileManager.default.createFile(atPath: repoB + "/.git", contents: Data("gitdir: ../x".utf8))
        // git olmayan düz dizin — yine listelenir
        _ = try makeDir("projects", "plainC")
        // gizli dizin — atlanır
        _ = try makeDir("projects", ".hidden")
        // düz dosya — atlanır
        FileManager.default.createFile(
            atPath: tempRoot.appendingPathComponent("projects/notes.txt").path,
            contents: Data()
        )

        let service = RepoService()
        await service.setRoots(
            projectsRoot: tempRoot.appendingPathComponent("projects").path,
            additionalPaths: []
        )
        let repos = await service.repos()

        XCTAssertEqual(repos.map(\.name), ["plainC", "repoA", "repoB"])
        XCTAssertEqual(repos.first { $0.name == "repoA" }?.isGitRepo, true)
        XCTAssertEqual(repos.first { $0.name == "repoB" }?.isGitRepo, true)
        XCTAssertEqual(repos.first { $0.name == "plainC" }?.isGitRepo, false)
        XCTAssertEqual(repos.first?.source, .projectsRoot)
    }

    func testAdditionalPathsAndFirstWinsDedup() async throws {
        let repoAPath = try makeDir("projects", "repoA", ".git")
        let repoA = (repoAPath as NSString).deletingLastPathComponent
        let extraRoot = try makeDir("extra")
        _ = try makeDir("extra", "repoX", ".git")
        let standalone = try makeDir("solo", ".git")
        let soloPath = (standalone as NSString).deletingLastPathComponent

        let service = RepoService()
        await service.setRoots(
            projectsRoot: tempRoot.appendingPathComponent("projects").path,
            additionalPaths: [
                AdditionalPath(id: "1", path: extraRoot, type: .root, label: "Extra"),
                AdditionalPath(id: "2", path: soloPath, type: .repo),
                // Dedup: projectsRoot'taki repoA tekrar — İLK kazanır
                AdditionalPath(id: "3", path: repoA, type: .repo),
            ]
        )
        let repos = await service.repos()

        XCTAssertEqual(repos.count, 3)
        let repoX = try XCTUnwrap(repos.first { $0.name == "repoX" })
        XCTAssertEqual(repoX.source, .additionalRoot(path: extraRoot, label: "Extra"))
        let solo = try XCTUnwrap(repos.first { $0.name == "solo" })
        XCTAssertEqual(solo.source, .standalone)
        // repoA ilk kaynaktan (projectsRoot) kalır
        XCTAssertEqual(repos.first { $0.name == "repoA" }?.source, .projectsRoot)
    }

    func testNonexistentRootIsSilentlySkipped() async {
        let service = RepoService()
        await service.setRoots(
            projectsRoot: tempRoot.appendingPathComponent("missing").path,
            additionalPaths: [
                AdditionalPath(id: "1", path: "/nonexistent/xyz", type: .repo)
            ]
        )
        let repos = await service.repos()
        XCTAssertTrue(repos.isEmpty)
    }

    func testRootWatcherEmitsReposChangedOnNewDirectory() async throws {
        let projects = try makeDir("projects")
        let service = RepoService(watchDebounce: 0.05)
        await service.setRoots(projectsRoot: projects, additionalPaths: [])

        // setRoots event'i bu subscribe'dan ÖNCE gitti — stream yalnız watcher
        // event'ini görür (AsyncStream Sendable; iterator task içinde kurulur)
        let stream = await service.events()
        _ = try makeDir("projects", "newRepo")

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertTrue(received, "watcher debounce sonrası reposChanged yayınlamalı")
    }
}
