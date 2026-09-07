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

    // MARK: - Karar 46: ham diff metni

    func testWorkingTreeDiffTextCoversTrackedAndUntrackedFiles() async throws {
        try "one\n".write(to: repoDir.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try git("add", "tracked.txt")
        try git("commit", "-m", "init")
        try "two\n".write(to: repoDir.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repoDir.appendingPathComponent("fresh.txt"), atomically: true, encoding: .utf8)

        let text = await service.workingTreeDiffText(repoPath: repoDir.path, files: ["tracked.txt", "fresh.txt"])

        XCTAssertTrue(text.contains("-one"))
        XCTAssertTrue(text.contains("+two"))
        XCTAssertTrue(text.contains("+new"), "untracked dosya /dev/null'a karşı eklenir")
        let outside = await service.workingTreeDiffText(repoPath: repoDir.path, files: ["../escape"])
        XCTAssertEqual(outside, "")
        let none = await service.workingTreeDiffText(repoPath: repoDir.path, files: [])
        XCTAssertEqual(none, "")
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

    /// GIT_TRACE ile blok içinde çalışan gerçek `git` süreçlerini sayar.
    private func withGitTrace(_ body: () async throws -> Void) async throws -> String {
        let traceFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-git-trace-\(UUID().uuidString).log")
        defer {
            unsetenv("GIT_TRACE")
            try? FileManager.default.removeItem(at: traceFile)
        }
        setenv("GIT_TRACE", traceFile.path, 1)
        try await body()
        return (try? String(contentsOf: traceFile, encoding: .utf8)) ?? ""
    }

    private static func gitRunCount(in trace: String) -> Int {
        trace.split(separator: "\n").filter { $0.contains("built-in: git ") }.count
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
    /// gösterir (`defaultBranch..branch`).
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

    // MARK: - Status (porcelain parse)

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

    /// Uzantısı masum ama içeriği binary olan dosya (ör. `.mp4` yerine `.dat`,
    /// uzantısız derlenmiş çıktı) metin olarak açılmaz — NUL sniff'i.
    func testReadFileRejectsBinaryContent() async throws {
        var bytes = Array("hello".utf8)
        bytes.append(0)
        bytes.append(contentsOf: Array("world".utf8))
        try Data(bytes).write(to: repoDir.appendingPathComponent("blob"))

        do {
            _ = try await service.readFile(repoPath: repoDir.path, file: "blob")
            XCTFail("binary içerik metin olarak okundu")
        } catch let error as LumiError {
            guard case .fileOperationFailed(let path, let detail) = error else {
                return XCTFail("beklenmeyen hata: \(error)")
            }
            XCTAssertEqual(path, "blob")
            XCTAssertTrue(detail.lowercased().contains("binary"), detail)
        }
    }

    func testReadFileRejectsOversizedFile() async throws {
        let big = Data(repeating: UInt8(ascii: "a"), count: GitService.maxTextPreviewBytes + 1)
        try big.write(to: repoDir.appendingPathComponent("huge.log"))

        do {
            _ = try await service.readFile(repoPath: repoDir.path, file: "huge.log")
            XCTFail("aşırı büyük dosya okundu")
        } catch let error as LumiError {
            guard case .fileOperationFailed(_, let detail) = error else {
                return XCTFail("beklenmeyen hata: \(error)")
            }
            XCTAssertTrue(detail.lowercased().contains("large"), detail)
        }
    }

    /// 1.12: guard `standardizedFileURL` ile symlink'i çözmüyordu — repo içindeki
    /// bir symlink repo DIŞINA işaret ettiğinde okuma geçiyordu.
    func testSymlinkEscapingRepoIsRejected() async throws {
        try write("safe.txt", "ok")
        try commitAll("base")

        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "secret".write(
            to: outside.appendingPathComponent("secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: repoDir.appendingPathComponent("link"),
            withDestinationURL: outside
        )

        do {
            _ = try await service.readFile(repoPath: repoDir.path, file: "link/secret.txt")
            XCTFail("symlink üzerinden repo dışına okuma yapıldı")
        } catch let error as LumiError {
            XCTAssertEqual(error, .pathOutsideRepo(path: "link/secret.txt"))
        }
        // Repo içi yol etkilenmez (/var ↔ /private/var canonicalize edilir)
        let safe = try await service.readFile(repoPath: repoDir.path, file: "safe.txt")
        XCTAssertEqual(safe, "ok")
    }

    /// 1.9: `commits` her çağrıda ayrıca tam bir `git branch --list`
    /// koşturuyordu (N branch → 2N process). Branch verilmediğinde default
    /// branch hesabına hiç gerek yok.
    func testCommitsWithoutBranchSpawnsSingleGitProcess() async throws {
        try write("a.txt", "v1")
        try commitAll("first")

        let trace = try await withGitTrace {
            _ = await service.commits(repoPath: repoDir.path, branch: nil)
        }
        XCTAssertEqual(
            Self.gitRunCount(in: trace), 1,
            "branch verilmediğinde tek git süreci yeterli:\n\(trace)"
        )
    }

    /// Branch verildiğinde default branch hesabı tek ek süreçle yapılır
    /// (`branch --list` + parse yerine hedefli `for-each-ref`).
    func testCommitsWithBranchSpawnsAtMostTwoGitProcesses() async throws {
        try write("a.txt", "v1")
        try commitAll("main first")
        try git("checkout", "-b", "feature")
        try write("b.txt", "x")
        try commitAll("feature only")

        let trace = try await withGitTrace {
            _ = await service.commits(repoPath: repoDir.path, branch: "feature")
        }
        XCTAssertLessThanOrEqual(Self.gitRunCount(in: trace), 2, trace)
    }

    // MARK: - Commit hata yolu (1.6)

    /// 1.6: `add` hata yolunda detail üretmek için `git add` İKİNCİ kez
    /// koşuyordu. GIT_TRACE ile gerçek çalıştırma sayısı ölçülür.
    func testCommitAddFailureRunsAddOnlyOnce() async throws {
        try write("safe.txt", "ok")
        try commitAll("base")

        let traceFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-git-trace-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: traceFile) }
        setenv("GIT_TRACE", traceFile.path, 1)
        defer { unsetenv("GIT_TRACE") }

        do {
            try await service.commit(
                repoPath: repoDir.path,
                message: "m",
                files: ["yok.txt"]
            )
            XCTFail("var olmayan dosyayla commit başarılı oldu")
        } catch let error as LumiError {
            guard case .gitFailed(let operation, let detail) = error else {
                return XCTFail("beklenmeyen hata: \(error)")
            }
            XCTAssertEqual(operation, "add")
            XCTAssertTrue(
                detail.contains("yok.txt"),
                "detail ilk add'in stderr'i olmalı, 'timeout' değil: \(detail)"
            )
        }

        let trace = (try? String(contentsOf: traceFile, encoding: .utf8)) ?? ""
        let addRuns = trace
            .split(separator: "\n")
            .filter { $0.contains("built-in: git add") }
            .count
        XCTAssertEqual(addRuns, 1, "git add ikinci kez koştu:\n\(trace)")
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
