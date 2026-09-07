import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// `PlasticService` orkestrasyonu: `cm` çözümü, komut satırları, sessiz-boş
/// hata yolu. Gerçek `cm` binary'sine dokunmaz.
final class PlasticServiceTests: XCTestCase {
    private let workspace = "/Users/me/wkspaces/Unity/sand_out"
    private let cm = "/usr/local/bin/cm"

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
}
