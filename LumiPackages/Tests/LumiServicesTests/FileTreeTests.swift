import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// File tree davranışları (spec/12 §9 + karar 7: gerçek git ignore semantiği —
/// nested .gitignore dahil; bilinçli sapma).
final class FileTreeTests: XCTestCase {
    private var repoDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
        try super.tearDownWithError()
    }

    private func git(_ args: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repoDir
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }

    private func makeFile(_ relative: String, _ content: String = "x") throws {
        let url = repoDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func node(_ tree: [FileTreeNode], _ path: String) -> FileTreeNode? {
        for entry in tree {
            if entry.path == path { return entry }
            if let found = node(entry.children, path) { return found }
        }
        return nil
    }

    func testGitIgnoreSemanticsIncludingNested() async throws {
        try git("init", "--initial-branch=main")
        try makeFile(".gitignore", "ignored-dir/\n*.tmp\n")
        try makeFile("src/.gitignore", "local-secret.txt\n")
        try makeFile("src/main.swift")
        try makeFile("src/local-secret.txt") // nested .gitignore ile ignored (karar 7!)
        try makeFile("ignored-dir/inner/deep.txt")
        try makeFile("scratch.tmp")
        try makeFile("README.md")

        let service = RepoService()
        let tree = await service.fileTree(repoPath: repoDir.path)

        // .git daima gizli
        XCTAssertNil(node(tree, ".git"))

        // Kök .gitignore kuralları
        let ignoredDir = try XCTUnwrap(node(tree, "ignored-dir"))
        XCTAssertTrue(ignoredDir.isIgnored)
        XCTAssertTrue(ignoredDir.children.isEmpty, "ignored klasöre İNİLMEZ")
        XCTAssertEqual(node(tree, "scratch.tmp")?.isIgnored, true)

        // Nested .gitignore — Electron yalnız kökü okurdu; karar 7 sapması
        XCTAssertEqual(node(tree, "src/local-secret.txt")?.isIgnored, true)
        XCTAssertEqual(node(tree, "src/main.swift")?.isIgnored, false)
        XCTAssertEqual(node(tree, "README.md")?.isIgnored, false)
    }

    func testHardcodedExcludesApplyWithoutGit() async throws {
        // Git OLMAYAN dizin: tek filtre hardcoded liste (spec/12 §9)
        try makeFile("node_modules/pkg/index.js")
        try makeFile("app.log")
        try makeFile(".env.local")
        try makeFile("main.py")

        let service = RepoService()
        let tree = await service.fileTree(repoPath: repoDir.path)

        let nodeModules = try XCTUnwrap(node(tree, "node_modules"))
        XCTAssertTrue(nodeModules.isIgnored)
        XCTAssertTrue(nodeModules.children.isEmpty)
        XCTAssertEqual(node(tree, "app.log")?.isIgnored, true)
        XCTAssertEqual(node(tree, ".env.local")?.isIgnored, true)
        XCTAssertEqual(node(tree, "main.py")?.isIgnored, false)
    }

    func testSortOrderFoldersThenNonIgnoredThenAlphabetical() async throws {
        try git("init", "--initial-branch=main")
        try makeFile(".gitignore", "zeta-ignored.txt\nignored-folder/\n")
        try makeFile("beta.txt")
        try makeFile("alpha.txt")
        try makeFile("zeta-ignored.txt")
        try makeFile("bravo-folder/x.txt")
        try makeFile("ignored-folder/y.txt")
        try makeFile("alpha-folder/z.txt")

        let service = RepoService()
        let tree = await service.fileTree(repoPath: repoDir.path)
        let names = tree.map(\.name)

        // 1) klasörler önce (ignored olmayan alfabetik, ignored klasör sonda)
        // 2) dosyalar: ignored olmayanlar alfabetik, ignored sonda
        XCTAssertEqual(names, [
            "alpha-folder", "bravo-folder", "ignored-folder",
            ".gitignore", "alpha.txt", "beta.txt", "zeta-ignored.txt",
        ])
    }
}
