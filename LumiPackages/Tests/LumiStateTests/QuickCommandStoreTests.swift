import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class QuickCommandStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var toasts: ToastStore!
    private var generator: FakeQuickCommandGenerator!
    private var scripts: FakeQuickCommandScriptWriter!
    private var store: QuickCommandStore!

    override func setUp() async throws {
        config = FakeConfigService()
        toasts = ToastStore()
        generator = FakeQuickCommandGenerator()
        scripts = FakeQuickCommandScriptWriter()
        store = QuickCommandStore(config: config, generator: generator, scripts: scripts, toasts: toasts)
    }

    func testSaveAppendsThenUpdatesInPlace() async {
        let first = ProjectQuickCommand(id: "1", projectPath: "/a", name: "  Build  ", script: "make")
        let second = ProjectQuickCommand(id: "2", projectPath: "/a", name: "Test", script: "make test")
        let saved = await store.save(first)
        await store.save(second)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.commands.map(\.name), ["Build", "Test"], "name is trimmed on save")

        var edited = store.commands[0]
        edited.script = "make all"
        await store.save(edited)
        let persisted = await config.config().projectQuickCommands
        XCTAssertEqual(persisted.map(\.id), ["1", "2"], "editing keeps the position")
        XCTAssertEqual(persisted.first?.script, "make all")
    }

    func testInvalidCommandIsNotWritten() async {
        let saved = await store.save(ProjectQuickCommand(projectPath: "/a", name: "", script: "ls"))
        XCTAssertFalse(saved)
        let writes = await config.configUpdateCount
        XCTAssertEqual(writes, 0)
    }

    func testCommandsAreFilteredByProjectAndDeleted() async {
        await store.save(ProjectQuickCommand(id: "1", projectPath: "/a", name: "A", script: "ls"))
        await store.save(ProjectQuickCommand(id: "2", projectPath: "/b", name: "B", script: "ls"))
        XCTAssertEqual(store.commands(for: "/b").map(\.id), ["2"])
        await store.delete(id: "2")
        XCTAssertTrue(store.commands(for: "/b").isEmpty)
        let persisted = await config.config().projectQuickCommands
        XCTAssertEqual(persisted.map(\.id), ["1"])
    }

    func testLoadReadsPersistedCommands() async {
        var seeded = AppConfig.defaults
        seeded.projectQuickCommands = [ProjectQuickCommand(id: "1", projectPath: "/a", name: "A", script: "ls")]
        await config.seed(seeded)
        await store.load()
        XCTAssertEqual(store.commands.map(\.id), ["1"])
    }

    func testWriteFailureKeepsListAndShowsToast() async {
        await config.setUpdateConfigError(.configIOFailed(file: "/x", detail: "disk full"))
        let saved = await store.save(ProjectQuickCommand(projectPath: "/a", name: "A", script: "ls"))
        XCTAssertFalse(saved)
        XCTAssertTrue(store.commands.isEmpty)
        XCTAssertFalse(toasts.toasts.isEmpty)
    }

    func testGenerateReturnsScriptWithoutSavingAndTracksFlight() async {
        await generator.setScript("make\n")
        await generator.setDelay(.milliseconds(50))
        let request = QuickCommandGenerationRequest(projectPath: "/a", projectName: "A", description: "build")
        let flight = Task { await store.generate(draftID: "d", request: request) }
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(store.isGenerating("d"))
        let duplicate = await store.generate(draftID: "d", request: request)
        XCTAssertNil(duplicate, "second request for the same draft is ignored")

        let script = await flight.value
        XCTAssertEqual(script, "make\n")
        XCTAssertFalse(store.isGenerating("d"))
        let writes = await config.configUpdateCount
        XCTAssertEqual(writes, 0, "generation never persists by itself")
        let requests = await generator.requests
        XCTAssertEqual(requests, [request])
    }

    func testGenerateFailureShowsToast() async {
        await generator.setError(.quickCommandGenerationFailed(detail: "boom"))
        let script = await store.generate(
            draftID: "d", request: .init(projectPath: "/a", projectName: "A", description: "x")
        )
        XCTAssertNil(script)
        XCTAssertFalse(toasts.toasts.isEmpty)
    }

    func testPrepareRunWritesResolvedScriptPerCheckout() async {
        let command = ProjectQuickCommand(id: "cmd", projectPath: "/p", name: "Open", script: "cd \"{path}\" && echo {branch}")
        let context = QuickCommandContext(path: "/w/review", projectPath: "/p", name: "review", branch: "feature/x")
        let line = await store.prepareRun(command, context: context)
        XCTAssertEqual(line, "sh '/lumi/quick-commands/cmd-review.sh'")
        let writes = await scripts.writes
        XCTAssertEqual(writes.first?.name, "cmd-review.sh")
        XCTAssertEqual(writes.first?.contents, "# Lumi action: Open\ncd \"/w/review\" && echo feature/x\n")
    }

    func testPrepareRunFailureShowsToast() async {
        await scripts.setError(.fileOperationFailed(path: "/x", detail: "denied"))
        let line = await store.prepareRun(
            ProjectQuickCommand(projectPath: "/p", name: "A", script: "ls"),
            context: QuickCommandContext(path: "/p", projectPath: "/p", name: "p", branch: "")
        )
        XCTAssertNil(line)
        XCTAssertFalse(toasts.toasts.isEmpty)
    }

    // MARK: - Start App (karar 93)

    func testStartAppAndActionsAreSeparatedPerProject() async {
        await store.save(ProjectQuickCommand(id: "a", projectPath: "/p", name: "Build", script: "make"))
        await store.save(ProjectQuickCommand(id: "s", projectPath: "/p", name: "Start App", script: "open .", role: .startApp))
        XCTAssertEqual(store.startApp(for: "/p")?.id, "s")
        XCTAssertEqual(store.actions(for: "/p").map(\.id), ["a"])
        XCTAssertNil(store.startApp(for: "/other"))
    }

    func testSavingEmptyStartAppRemovesIt() async {
        var startApp = ProjectQuickCommand(id: "s", projectPath: "/p", name: "Start App", script: "open .", role: .startApp)
        await store.save(startApp)
        startApp.script = "  \n"
        let saved = await store.save(startApp)
        XCTAssertTrue(saved)
        XCTAssertNil(store.startApp(for: "/p"))
        let persisted = await config.config().projectQuickCommands
        XCTAssertTrue(persisted.isEmpty)
    }

    func testSecondStartAppReplacesTheFirst() async {
        await store.save(ProjectQuickCommand(id: "s1", projectPath: "/p", name: "Start App", script: "a", role: .startApp))
        await store.save(ProjectQuickCommand(id: "s2", projectPath: "/p", name: "Start App", script: "b", role: .startApp))
        XCTAssertEqual(store.commands.filter { $0.role == .startApp }.map(\.id), ["s2"])
    }
}
