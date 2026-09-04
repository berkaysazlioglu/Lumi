import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Refactor 3.10: path guard'ı `GitService`den çıkıp paylaşılan bir tipe indi
/// (karar 11 — TÜM path alan yollarda kök-içi doğrulaması).
final class RepoPathGuardTests: XCTestCase {
    private let guardian = RepoPathGuard()
    private var repoRoot = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoRoot = NSTemporaryDirectory() + "lumi-guard-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: repoRoot, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: repoRoot)
        try super.tearDownWithError()
    }

    func testResolvesRelativePathInsideRepo() throws {
        let resolved = try guardian.resolve(repoPath: repoRoot, relativePath: "src/main.swift")

        XCTAssertTrue(resolved.hasSuffix("/src/main.swift"))
    }

    func testRejectsParentTraversal() {
        XCTAssertThrowsError(
            try guardian.resolve(repoPath: repoRoot, relativePath: "../../etc/passwd")
        ) { error in
            XCTAssertEqual(error as? LumiError, .pathOutsideRepo(path: "../../etc/passwd"))
        }
    }

    func testRejectsSymlinkPointingOutsideRepo() throws {
        // Repo içindeki bir symlink repo DIŞINA işaret ediyorsa guard geçilmemeli.
        let linkPath = repoRoot + "/escape"
        try FileManager.default.createSymbolicLink(
            atPath: linkPath, withDestinationPath: "/etc"
        )

        XCTAssertThrowsError(
            try guardian.resolve(repoPath: repoRoot, relativePath: "escape/passwd")
        )
    }

    func testRepoRootItselfIsAllowed() throws {
        let resolved = try guardian.resolve(repoPath: repoRoot, relativePath: ".")

        XCTAssertEqual(resolved, RepoPathGuard.canonical(repoRoot))
    }

    func testSiblingPrefixIsNotConsideredInside() {
        // "/a/repo" kökü "/a/repo-other" path'ini kabul etmemeli (prefix tuzağı).
        XCTAssertFalse(
            guardian.isInside(anyOf: ["/tmp/repo"], path: "/tmp/repo-other/file.txt")
        )
        XCTAssertTrue(guardian.isInside(anyOf: ["/tmp/repo"], path: "/tmp/repo/file.txt"))
    }

    func testEmptyRootListAllowsNothing() {
        XCTAssertFalse(guardian.isInside(anyOf: [], path: "/tmp/anything"))
        XCTAssertFalse(guardian.isInside(anyOf: [""], path: "/tmp/anything"))
    }

    func testTildeRootIsExpanded() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Projects/x")

        XCTAssertTrue(guardian.isInside(anyOf: ["~/Projects"], path: path))
    }
}
