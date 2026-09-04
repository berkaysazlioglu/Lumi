import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Devasa/kötü biçimli köklere karşı tarama güvenliği (karar 28):
/// symlink takip edilmez, girdi/derinlik tavanı, Unity/Xcode gürültü exclude'ları.
final class FileTreeBuilderSafetyTests: XCTestCase {
    private var rootDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-tree-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootDir)
        try super.tearDownWithError()
    }

    private func makeFile(_ relative: String) throws {
        let url = rootDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "x".write(to: url, atomically: true, encoding: .utf8)
    }

    private func node(_ tree: [FileTreeNode], _ path: String) -> FileTreeNode? {
        for entry in tree {
            if entry.path == path { return entry }
            if let found = node(entry.children, path) { return found }
        }
        return nil
    }

    private func countNodes(_ tree: [FileTreeNode]) -> Int {
        tree.reduce(0) { $0 + 1 + countNodes($1.children) }
    }

    func testSymlinkLoopIsNotFollowed() throws {
        try makeFile("real/inner/file.txt")
        // real/inner/loop → ../.. (kökün kendisi): takip edilirse tarama hiç bitmez
        try FileManager.default.createSymbolicLink(
            atPath: rootDir.appendingPathComponent("real/inner/loop").path,
            withDestinationPath: "../.."
        )

        let tree = FileTreeBuilder.build(root: rootDir.path, ignoredPaths: [])

        let loop = try XCTUnwrap(node(tree, "real/inner/loop"))
        XCTAssertEqual(loop.type, .file, "symlink dizin olarak görünmez (Electron dirent paritesi)")
        XCTAssertTrue(loop.children.isEmpty)
        XCTAssertEqual(countNodes(tree), 4) // real, inner, file.txt, loop
    }

    func testBrokenSymlinkIsOmitted() throws {
        try makeFile("keep.txt")
        try FileManager.default.createSymbolicLink(
            atPath: rootDir.appendingPathComponent("dangling").path,
            withDestinationPath: "does-not-exist"
        )

        let tree = FileTreeBuilder.build(root: rootDir.path, ignoredPaths: [])

        XCTAssertNil(node(tree, "dangling"), "kırık symlink eski davranış gibi elenir")
        XCTAssertNotNil(node(tree, "keep.txt"))
    }

    func testEntryCapStopsDescending() throws {
        for index in 0..<10 {
            try makeFile("dir\(index)/a.txt")
            try makeFile("dir\(index)/b.txt")
        }

        let limits = FileTreeBuilder.Limits(maxEntries: 12, maxDepth: 32)
        let tree = FileTreeBuilder.build(root: rootDir.path, ignoredPaths: [], limits: limits)

        XCTAssertEqual(tree.count, 10, "kök seviyesi daima tam listelenir")
        XCTAssertLessThanOrEqual(countNodes(tree), 12 + 10, "tavan aşıldığında alt dizinlere inilmez")
        XCTAssertLessThan(countNodes(tree), 30)
    }

    func testDepthCapStopsDescending() throws {
        try makeFile("a/b/c/d/leaf.txt")

        let limits = FileTreeBuilder.Limits(maxEntries: 1_000, maxDepth: 2)
        let tree = FileTreeBuilder.build(root: rootDir.path, ignoredPaths: [], limits: limits)

        XCTAssertNotNil(node(tree, "a/b"))
        XCTAssertNil(node(tree, "a/b/c"), "maxDepth=2 → üçüncü seviye taranmaz")
    }

    func testUnityAndXcodeNoiseIsExcluded() throws {
        try makeFile("Library/ArtifactDB")
        try makeFile("Temp/x")
        try makeFile("Logs/y.log")
        try makeFile("obj/z")
        try makeFile("DerivedData/w")
        try makeFile("Assets/Main.cs")

        let tree = FileTreeBuilder.build(root: rootDir.path, ignoredPaths: [])

        for name in ["Library", "Temp", "Logs", "obj", "DerivedData"] {
            let folder = try XCTUnwrap(node(tree, name), name)
            XCTAssertTrue(folder.isIgnored, "\(name) ignored olmalı")
            XCTAssertTrue(folder.children.isEmpty, "\(name) içine inilmez")
        }
        XCTAssertEqual(node(tree, "Assets/Main.cs")?.isIgnored, false)
    }
}
