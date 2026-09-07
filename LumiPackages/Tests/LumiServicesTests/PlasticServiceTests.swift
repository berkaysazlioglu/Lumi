import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// `PlasticService` orkestrasyonu: `cm` çözümü, komut satırları, sessiz-boş
/// hata yolu. Gerçek `cm` binary'sine dokunmaz.
final class PlasticServiceTests: XCTestCase {
    private let workspace = "/Users/me/wkspaces/Unity/sand_out"
    private let cm = "/usr/local/bin/cm"

    /// Guard `resolvingSymlinksInPath` ile canonicalize eder; var olmayan bir kök
    /// dizin gibi çözülmez. Yazma testleri gerçek bir temp dizin kullanır.
    private func makeTemporaryWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeService(runner: FakeProcessRunner, cmInstalled: Bool = true) -> (PlasticService, FakeBinaryLocator) {
        let locator = FakeBinaryLocator(paths: cmInstalled ? ["cm": cm] : [:])
        return (PlasticService(runner: runner, locator: locator), locator)
    }

    func testMissingCLIYieldsEmptyResultsWithoutSpawningProcesses() async {
        let runner = FakeProcessRunner()
        let (service, locator) = makeService(runner: runner, cmInstalled: false)

        let available = await service.isCLIAvailable()
        let info = await service.workspaceInfo(workspacePath: workspace)
        let status = await service.status(workspacePath: workspace)
        let changesets = await service.recentChangesets(workspacePath: workspace, limit: 10)

        XCTAssertFalse(available)
        XCTAssertNil(info)
        XCTAssertTrue(status.isEmpty)
        XCTAssertTrue(changesets.isEmpty)
        let invocations = await runner.invocations
        XCTAssertTrue(invocations.isEmpty)
        let lookups = await locator.lookups
        XCTAssertEqual(lookups, ["cm"], "binary yalnız bir kez aranır")
    }

    func testWorkspaceInfoCombinesHeaderAndSelector() async {
        let runner = FakeProcessRunner()
        await runner.stub(commandLine: "\(cm) status --header --machinereadable --fieldseparator=|",
                          with: .success("STATUS|2105|sand_out|uncosoft@cloud\n"))
        await runner.stub(commandLine: "\(cm) showselector",
                          with: .success("rep \"sand_out@uncosoft@cloud\"\n  path \"/\"\n    smartbranch \"/main\" changeset \"2105\"\n"))
        let (service, _) = makeService(runner: runner)

        let info = await service.workspaceInfo(workspacePath: workspace)

        XCTAssertEqual(info, PlasticWorkspaceInfo(changesetID: 2105, repository: "sand_out", server: "uncosoft@cloud", branch: "/main"))
        let directories = await runner.invocations.map(\.currentDirectory)
        XCTAssertEqual(directories, [workspace, workspace])
    }

    func testNonWorkspaceDirectoryReturnsNilQuietly() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 1, stdout: "/tmp is not in a workspace.\n"))
        let (service, _) = makeService(runner: runner)

        let info = await service.workspaceInfo(workspacePath: "/tmp")
        let status = await service.status(workspacePath: "/tmp")

        XCTAssertNil(info)
        XCTAssertTrue(status.isEmpty)
    }

    func testStatusUsesMachineReadableAllAndRelativizes() async {
        let runner = FakeProcessRunner()
        await runner.stub(
            commandLine: "\(cm) status --short --machinereadable --fieldseparator=| --all --cutignored",
            with: .success("CH|\(workspace)/Assets/A.cs|False|NO_MERGES\nPR|\(workspace)/new.txt|False|NO_MERGES\n")
        )
        let (service, _) = makeService(runner: runner)

        let status = await service.status(workspacePath: workspace)

        XCTAssertEqual(status, [
            PlasticFileChange(path: "Assets/A.cs", status: .modified),
            PlasticFileChange(path: "new.txt", status: .untracked),
        ])
    }

    func testRecentChangesetsQueriesNewestFirstWithLimitAndISODates() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("7\u{1F}/main\u{1F}owner\u{1F}2026-07-07T11:24:09+03:00\u{1F}6\u{1F}fix\n"))
        let (service, _) = makeService(runner: runner)

        let changesets = await service.recentChangesets(workspacePath: workspace, limit: 200)

        XCTAssertEqual(changesets.map(\.changesetID), [7])
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.arguments, [
            "find", "changesets order by changesetid desc limit 200",
            "--format=" + ["{changesetid}", "{branch}", "{owner}", "{date}", "{parent}", "{comment}"].joined(separator: "\u{1F}"),
            "--dateformat=yyyy-MM-ddTHH:mm:sszzz",
            "--nototal",
        ])
        XCTAssertEqual(invocation?.timeout, PlasticService.commandTimeout)
    }

    func testTimeoutIsSilentEmpty() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.timeout)
        let (service, _) = makeService(runner: runner)

        let changesets = await service.recentChangesets(workspacePath: workspace, limit: 5)
        let info = await service.workspaceInfo(workspacePath: workspace)

        XCTAssertTrue(changesets.isEmpty)
        XCTAssertNil(info)
    }

    // MARK: Yazma

    func testCheckinPassesResolvedPathsCommentAndInclusionFlags() async throws {
        let runner = FakeProcessRunner()
        let root = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.resolvingSymlinksInPath().path
        let (service, _) = makeService(runner: runner)

        try await service.checkin(workspacePath: root.path, message: "fix lid", files: ["Assets/A.cs", "new.txt"])

        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, cm)
        XCTAssertEqual(invocation?.arguments, [
            "checkin", canonicalRoot + "/Assets/A.cs", canonicalRoot + "/new.txt",
            "-c=fix lid", "--all", "--applychanged", "--private", "--noshowchangeset",
        ])
    }

    func testCheckinRejectsPathsOutsideWorkspaceBeforeSpawning() async {
        let runner = FakeProcessRunner()
        let (service, _) = makeService(runner: runner)

        do {
            try await service.checkin(workspacePath: workspace, message: "x", files: ["../secret"])
            XCTFail("kök dışı path kabul edilmemeli")
        } catch let error as LumiError {
            guard case .pathOutsideRepo = error else { return XCTFail("beklenmeyen hata: \(error)") }
        } catch { XCTFail("beklenmeyen hata: \(error)") }
        let invocations = await runner.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testCheckinFailureSurfacesStderrDetail() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 1, stdout: "Assembling checkin data\n", stderr: "Error: There are no changes in the workspace\n"))
        let root = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = makeService(runner: runner)

        do {
            try await service.checkin(workspacePath: root.path, message: "x", files: ["a.cs"])
            XCTFail("exit 1 hata fırlatmalı")
        } catch let error as LumiError {
            guard case .plasticFailed(let operation, let detail) = error else { return XCTFail("beklenmeyen hata: \(error)") }
            XCTAssertEqual(operation, "checkin")
            XCTAssertEqual(detail, "Error: There are no changes in the workspace")
        } catch { XCTFail("beklenmeyen hata: \(error)") }
    }

    func testUndoRunsCMUndoWithResolvedPathsAndMissingCLIThrowsCLINotFound() async throws {
        let runner = FakeProcessRunner()
        let root = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = makeService(runner: runner)
        try await service.undo(workspacePath: root.path, files: ["Assets/A.cs"])
        let arguments = await runner.invocations.first?.arguments
        XCTAssertEqual(arguments?.first, "undo")
        XCTAssertEqual(arguments?.last?.hasSuffix("/Assets/A.cs"), true)

        let (missing, _) = makeService(runner: FakeProcessRunner(), cmInstalled: false)
        do {
            try await missing.undo(workspacePath: root.path, files: ["a"])
            XCTFail("cm yokken hata fırlatmalı")
        } catch let error as LumiError {
            guard case .cliNotFound(let binary) = error else { return XCTFail("beklenmeyen hata: \(error)") }
            XCTAssertEqual(binary, "cm")
        } catch { XCTFail("beklenmeyen hata: \(error)") }
    }

    // MARK: Diff metni (karar 47)

    func testWorkingTreeDiffTextUsesCMCatBaseAndRewritesHeaders() async throws {
        let runner = FakeProcessRunner()
        let root = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.resolvingSymlinksInPath().path
        try "new\n".write(to: root.appendingPathComponent("Assets/New.cs".replacingOccurrences(of: "Assets/", with: "")), atomically: true, encoding: .utf8)
        await runner.stub(executable: "/usr/bin/diff", with: .failure(exitCode: 1, stdout: "--- /tmp/base\t2026\n+++ \(canonicalRoot)/A.cs\t2026\n@@ -1 +1 @@\n-old\n+new\n"))
        let (service, _) = makeService(runner: runner)

        let text = await service.workingTreeDiffText(
            workspacePath: root.path, changesetID: 214,
            changes: [
                PlasticFileChange(path: "A.cs", status: .modified),
                PlasticFileChange(path: "Gone.cs", status: .deleted),
                PlasticFileChange(path: "New.cs", status: .untracked),
            ]
        )

        XCTAssertTrue(text.hasPrefix("--- a/A.cs\n+++ b/A.cs\n@@ -1 +1 @@\n-old\n+new\n"), text)
        XCTAssertTrue(text.contains("--- a/Gone.cs\n+++ /dev/null\n(deleted)\n"))
        XCTAssertTrue(text.contains("--- /dev/null\n+++ b/New.cs\n"))
        let invocations = await runner.invocations
        let cat = invocations.first { $0.arguments.first == "cat" }
        XCTAssertEqual(cat?.executable, cm)
        XCTAssertEqual(cat?.arguments[1], "rev:\(canonicalRoot)/A.cs#cs:214")
        XCTAssertTrue(cat?.arguments[2].hasPrefix("--file=") ?? false)
        let diffs = invocations.filter { $0.executable == "/usr/bin/diff" }
        XCTAssertEqual(diffs.count, 2, "değişen + eklenen; silinen için diff koşmaz")
        XCTAssertTrue(diffs.contains { Array($0.arguments.prefix(2)) == ["-u", "/dev/null"] }, "eklenen dosya /dev/null'a karşı (sıra paralel yüzünden serbest)")
    }

    func testWorkingTreeDiffTextSkipsFilesWhoseBaseCannotBeFetched() async throws {
        let runner = FakeProcessRunner()
        await runner.stub(executable: cm, with: .failure(exitCode: 1, stderr: "The specified revision couldn't be found"))
        let root = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = makeService(runner: runner)

        let text = await service.workingTreeDiffText(workspacePath: root.path, changesetID: 1, changes: [PlasticFileChange(path: "A.cs", status: .modified)])

        XCTAssertEqual(text, "")
    }

    func testWorkingTreeDiffTextFetchesBasesConcurrentlyButKeepsOrder() async throws {
        let runner = FakeProcessRunner()
        let root = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        await runner.stub(executable: cm, with: .success(delay: .milliseconds(40)))
        await runner.stub(executable: "/usr/bin/diff", with: .failure(exitCode: 1, stdout: "--- x\n+++ y\n@@\n+line\n"))
        let (service, _) = makeService(runner: runner)
        let changes = (0 ..< 12).map { PlasticFileChange(path: "F\($0).cs", status: .modified) }

        let started = Date()
        let text = await service.workingTreeDiffText(workspacePath: root.path, changesetID: 1, changes: changes)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 0.40, "12 × 40 ms sıralı 0.48 sn olurdu; paralel çok daha kısa")
        let headers = text.split(separator: "\n").filter { $0.hasPrefix("+++ b/") }.map(String.init)
        XCTAssertEqual(headers, (0 ..< 12).map { "+++ b/F\($0).cs" }, "çıktı sırası changes sırasıdır")
        let peak = await runner.maxConcurrentInvocations
        XCTAssertLessThanOrEqual(peak, PlasticService.maxConcurrentDiffs + 1)
    }
}
