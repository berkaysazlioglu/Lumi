import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// GitService entegrasyon testleri — gerçek temp git repo'larıyla
/// (design/04 faz 4 çıkış kriterleri: defaultBranch..branch semantiği,
/// porcelain parse, path-traversal guard).
final class GitServiceTests: XCTestCase {
    private var repoDir: URL!
    private let service = GitService()

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try git("init", "--initial-branch=main")
        try git("config", "user.email", "test@lumi.local")
        try git("config", "user.name", "Lumi Test")
        try git("config", "commit.gpgsign", "false")
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
        guard process.terminationStatus == 0 else {
            throw LumiError.gitFailed(operation: args.first ?? "", detail: "test setup failed")
        }
    }

    private func write(_ name: String, _ content: String) throws {
        try content.write(
            to: repoDir.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    private func commitAll(_ message: String) throws {
        try git("add", "-A")
        try git("commit", "-m", message)
    }

    // MARK: - Branch / log semantiği

    func testBranchesListsCurrentFlag() async throws {
        try write("a.txt", "hello")
        try commitAll("initial")
        try git("branch", "feature")

        let branches = await service.branches(repoPath: repoDir.path)
        XCTAssertEqual(Set(branches.map(\.name)), Set(["main", "feature"]))
        XCTAssertEqual(branches.first { $0.isCurrent }?.name, "main")
    }

    /// Faz 4 çıkış kriteri: feature branch yalnız KENDİNE ÖZGÜ commit'leri
    /// gösterir (`defaultBranch..branch` — spec/12 §2).
    func testFeatureBranchShowsOnlyUniqueCommits() async throws {
        try write("a.txt", "v1")
        try commitAll("main first")
        try write("a.txt", "v2")
        try commitAll("main second")
        try git("checkout", "-b", "feature")
        try write("b.txt", "feature work")
        try commitAll("feature only commit")

        let featureCommits = await service.commits(repoPath: repoDir.path, branch: "feature")
        XCTAssertEqual(featureCommits.map(\.message), ["feature only commit"])

        let mainCommits = await service.commits(repoPath: repoDir.path, branch: "main")
        XCTAssertEqual(mainCommits.map(\.message), ["main second", "main first"])
        XCTAssertEqual(mainCommits.first?.shortHash.count, 7)
        XCTAssertEqual(mainCommits.first?.author, "Lumi Test")
    }

    func testNonGitDirectoryReturnsEmptyQuietly() async throws {
        let plain = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }

        let branches = await service.branches(repoPath: plain.path)
        let commits = await service.commits(repoPath: plain.path, branch: nil)
        let status = await service.status(repoPath: plain.path)
        XCTAssertTrue(branches.isEmpty)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertTrue(status.isEmpty)
    }

    // MARK: - Status (porcelain parse, spec/12 §4)

    func testStatusMappingSimplified() async throws {
        try write("tracked.txt", "v1")
        try write("to-delete.txt", "bye")
        try write("to-rename.txt", "moving")
        try commitAll("base")

        try write("tracked.txt", "v2") // M
        try write("brand-new.txt", "new") // U (untracked)
        try write("staged-new.txt", "staged")
        try git("add", "staged-new.txt") // A
        try FileManager.default.removeItem(at: repoDir.appendingPathComponent("to-delete.txt")) // D
        try git("mv", "to-rename.txt", "renamed.txt") // R → to path

        let status = await service.status(repoPath: repoDir.path)
        let byPath = Dictionary(uniqueKeysWithValues: status.map { ($0.path, $0.status) })

        XCTAssertEqual(byPath["tracked.txt"], .modified)
        XCTAssertEqual(byPath["brand-new.txt"], .untracked)
        XCTAssertEqual(byPath["staged-new.txt"], .added)
        XCTAssertEqual(byPath["to-delete.txt"], .deleted)
        XCTAssertEqual(byPath["renamed.txt"], .renamed, "rename'de to path alınmalı")
        XCTAssertNil(byPath["to-rename.txt"])
    }

    // MARK: - Commit akışı

    func testCommitStagesAndCommitsSelectedFiles() async throws {
        try write("a.txt", "v1")
        try commitAll("base")
        try write("a.txt", "v2")
        try write("b.txt", "new file")

        try await service.commit(
            repoPath: repoDir.path,
            message: "feat: both files",
            files: ["a.txt", "b.txt"]
        )

        let status = await service.status(repoPath: repoDir.path)
        XCTAssertTrue(status.isEmpty, "commit sonrası working tree temiz olmalı")
        let commits = await service.commits(repoPath: repoDir.path, branch: nil)
        XCTAssertEqual(commits.first?.message, "feat: both files")
    }

    func testCommitWithNoFilesThrows() async {
        do {
            try await service.commit(repoPath: repoDir.path, message: "x", files: [])
            XCTFail("boş dosya listesi hata fırlatmalı (karar 5 — sessiz değil)")
        } catch let error as LumiError {
            guard case .gitFailed = error else {
                return XCTFail("beklenmeyen hata: \(error)")
            }
        } catch {
            XCTFail("LumiError bekleniyordu")
        }
    }

    // MARK: - Path traversal guard (faz 4 çıkış kriteri, karar 11)

    func testPathTraversalGuardsAllFileAPIs() async throws {
        try write("safe.txt", "ok")
        try commitAll("base")

        let escapes = ["../outside.txt", "../../etc/passwd", "a/../../escape"]
        for escape in escapes {
            do {
                _ = try await service.readFile(repoPath: repoDir.path, file: escape)
                XCTFail("readFile traversal'a izin verdi: \(escape)")
            } catch let error as LumiError {
                XCTAssertEqual(error, .pathOutsideRepo(path: escape))
            }
            do {
                _ = try await service.fileDiff(repoPath: repoDir.path, file: escape)
                XCTFail("fileDiff traversal'a izin verdi: \(escape)")
            } catch let error as LumiError {
                XCTAssertEqual(error, .pathOutsideRepo(path: escape))
            }
        }
        // Repo içi path normal çalışır
        let content = try await service.readFile(repoPath: repoDir.path, file: "safe.txt")
        XCTAssertEqual(content, "ok")
    }

    // MARK: - Diff'ler

    func testFileDiffForTrackedModification() async throws {
        try write("code.swift", "let a = 1\nlet b = 2\n")
        try commitAll("base")
        try write("code.swift", "let a = 1\nlet b = 99\n")

        let diff = try await service.fileDiff(repoPath: repoDir.path, file: "code.swift")
        XCTAssertEqual(diff.hunks.count, 1)
        let kinds = diff.hunks[0].lines.map(\.kind)
        XCTAssertTrue(kinds.contains(.deletion))
        XCTAssertTrue(kinds.contains(.addition))
        XCTAssertTrue(diff.hunks[0].lines.contains { $0.text == "let b = 99" })
    }

    func testFileDiffForUntrackedIsAllAdditions() async throws {
        try write("a.txt", "x")
        try commitAll("base")
        try write("fresh.txt", "line1\nline2\n")

        let diff = try await service.fileDiff(repoPath: repoDir.path, file: "fresh.txt")
        let lines = diff.hunks.flatMap(\.lines)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { $0.kind == .addition })
    }

    func testCommitFilesAndLazyFileDiff() async throws {
        try write("one.txt", "first\n")
        try commitAll("root commit")
        try write("one.txt", "first changed\n")
        try write("two.txt", "second\n")
        try commitAll("second commit")

        let commits = await service.commits(repoPath: repoDir.path, branch: nil)
        let secondSha = try XCTUnwrap(commits.first?.hash)
        let rootSha = try XCTUnwrap(commits.last?.hash)

        // Karar 6: yalnız dosya listesi
        let files = await service.commitFiles(repoPath: repoDir.path, sha: secondSha)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.status) }),
            ["one.txt": .modified, "two.txt": .added]
        )

        // Lazy tek dosya diff'i
        let diff = try await service.commitFileDiff(
            repoPath: repoDir.path, sha: secondSha, file: "one.txt"
        )
        XCTAssertTrue(diff.hunks.flatMap(\.lines).contains {
            $0.kind == .addition && $0.text == "first changed"
        })

        // Root commit'te de çalışır (parent yokluğu kenar durumu)
        let rootFiles = await service.commitFiles(repoPath: repoDir.path, sha: rootSha)
        XCTAssertEqual(rootFiles.map(\.path), ["one.txt"])
        let rootDiff = try await service.commitFileDiff(
            repoPath: repoDir.path, sha: rootSha, file: "one.txt"
        )
        XCTAssertTrue(rootDiff.hunks.flatMap(\.lines).allSatisfy { $0.kind == .addition })
    }

    // MARK: - Görsel önizleme (karar 21)

    /// PNG imzasıyla başlayan, birbirinden farklı sahte binary içerikler.
    private func pngBytes(_ marker: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, marker])
    }

    private func writeBinary(_ name: String, _ data: Data) throws {
        try data.write(to: repoDir.appendingPathComponent(name))
    }

    func testImagePreviewReturnsBothSidesForModifiedImage() async throws {
        try writeBinary("logo.png", pngBytes(1))
        try commitAll("add image")
        try writeBinary("logo.png", pngBytes(2))
        try commitAll("change image")

        let commits = await service.commits(repoPath: repoDir.path, branch: nil)
        let latest = try XCTUnwrap(commits.first?.hash)

        let preview = await service.imagePreview(
            repoPath: repoDir.path, file: "logo.png", sha: latest
        )
        XCTAssertEqual(preview.before, pngBytes(1))
        XCTAssertEqual(preview.after, pngBytes(2))
        XCTAssertFalse(preview.isTooLarge)
    }

    func testImagePreviewHasNoBeforeSideInRootCommit() async throws {
        try writeBinary("logo.png", pngBytes(1))
        try commitAll("add image")

        let commits = await service.commits(repoPath: repoDir.path, branch: nil)
        let root = try XCTUnwrap(commits.first?.hash)

        let preview = await service.imagePreview(
            repoPath: repoDir.path, file: "logo.png", sha: root
        )
        XCTAssertNil(preview.before) // parent yok → eklenen dosya
        XCTAssertEqual(preview.after, pngBytes(1))
        XCTAssertTrue(preview.hasContent)
    }

    func testImagePreviewWithoutShaComparesHeadWithWorkingTree() async throws {
        try writeBinary("logo.png", pngBytes(1))
        try commitAll("add image")
        try writeBinary("logo.png", pngBytes(9)) // commit edilmemiş değişiklik

        let preview = await service.imagePreview(
            repoPath: repoDir.path, file: "logo.png", sha: nil
        )
        XCTAssertEqual(preview.before, pngBytes(1))
        XCTAssertEqual(preview.after, pngBytes(9))
    }

    func testImagePreviewOfUntrackedFileHasOnlyAfterSide() async throws {
        try write("a.txt", "seed")
        try commitAll("initial")
        try writeBinary("new.png", pngBytes(3))

        let preview = await service.imagePreview(
            repoPath: repoDir.path, file: "new.png", sha: nil
        )
        XCTAssertNil(preview.before)
        XCTAssertEqual(preview.after, pngBytes(3))
    }

    /// Karar 11: path-traversal guard TÜM path alan metodlarda — burada sessiz
    /// (boş önizleme), çünkü imagePreview liste operasyonları gibi throw etmez.
    func testImagePreviewRejectsPathOutsideRepo() async throws {
        try write("a.txt", "seed")
        try commitAll("initial")

        let preview = await service.imagePreview(
            repoPath: repoDir.path, file: "../../etc/hosts", sha: nil
        )
        XCTAssertFalse(preview.hasContent)
        XCTAssertFalse(preview.isTooLarge)
    }
}
