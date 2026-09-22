import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class QuickCommandStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var toasts: ToastStore!
    private var store: QuickCommandStore!

    override func setUp() async throws {
        config = FakeConfigService()
        toasts = ToastStore()
        store = QuickCommandStore(config: config, toasts: toasts)
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
}
