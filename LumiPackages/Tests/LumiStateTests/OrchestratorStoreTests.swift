import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 123: orchestrator popup'taki etkileşimli bir Codex terminalidir —
/// kendi terminal yöneticisinde açılır, thread'i hook'tan öğrenilip sürdürülür.
@MainActor
final class OrchestratorStoreTests: XCTestCase {
    private var terminal: FakeTerminalService!
    private var launcher: FakeOrchestratorLauncher!
    private var config: FakeConfigService!
    private var control: FakeOrchestratorControlServer!

    override func setUp() async throws {
        terminal = FakeTerminalService()
        launcher = FakeOrchestratorLauncher()
        config = FakeConfigService()
        control = FakeOrchestratorControlServer()
    }

    private func makeStore(watchList: OrchestratorWatchList = OrchestratorWatchList()) -> OrchestratorStore {
        let store = OrchestratorStore(
            terminal: terminal,
            viewProvider: FakeTerminalViewProvider(),
            launcher: launcher,
            config: config,
            workingDirectory: "/home/.lumi/orchestrator",
            control: control,
            tools: NoTools(),
            watchList: watchList,
            promptContext: { (#"{"projects":[{"name":"api"}]}"#, [#""login" (t-1, working)"#]) },
            codexHome: { "/codex-home" }
        )
        store.start()
        return store
    }

    /// Olay tüketicisi işlesin.
    private func drain() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    private func storedThread() async -> String? {
        await config.uiState().orchestratorCodexThreadID
    }

    // MARK: - Açılış

    func testFirstActivationOpensFreshCodexWithDynamicInstructions() async throws {
        let store = makeStore()

        await store.activate()

        let request = try XCTUnwrap(launcher.requests.first)
        XCTAssertNil(request.resumeThreadID)
        XCTAssertEqual(request.codexHome, "/codex-home")
        XCTAssertEqual(request.control, FakeOrchestratorControlServer.endpoint, "MCP ucu Codex'e gider")
        XCTAssertTrue(request.instructions.contains(#""name":"api""#), "aktif projeler talimatta")
        XCTAssertTrue(request.instructions.contains(#""login" (t-1, working)"#), "izlenen terminaller talimatta")
        for tool in OrchestratorTools.specs.map(\.name) {
            XCTAssertTrue(request.instructions.contains("`\(tool)`"), "araç kataloğunda yok: \(tool)")
        }
        let spawn = try XCTUnwrap(terminal.spawnCalls.first)
        XCTAssertEqual(spawn.repoPath, "/home/.lumi/orchestrator")
        XCTAssertEqual(spawn.command, "codex new")
        XCTAssertEqual(spawn.environment["LUMI_MCP_TOKEN"], "fake-token")
        XCTAssertEqual(store.phase, .running)
        XCTAssertEqual(store.terminalID, terminal.spawnedMetas.first?.id)
        XCTAssertEqual(control.startCount, 1)
    }

    func testActivateIsIdempotentWhileRunning() async {
        let store = makeStore()
        await store.activate()
        await store.activate()
        XCTAssertEqual(terminal.spawnCalls.count, 1)
    }

    func testThreadFromHookIsPersistedAndResumedNextTime() async throws {
        let store = makeStore()
        await store.activate()
        let id = try XCTUnwrap(store.terminalID)

        terminal.emit(.codexSessionIDChanged(id, "thread-1"))
        await drain()

        XCTAssertEqual(store.threadID, "thread-1")
        let saved = await storedThread()
        XCTAssertEqual(saved, "thread-1")

        let next = OrchestratorStore(
            terminal: FakeTerminalService(), viewProvider: FakeTerminalViewProvider(),
            launcher: launcher, config: config, workingDirectory: "/w"
        )
        await next.activate()
        XCTAssertEqual(launcher.requests.last?.resumeThreadID, "thread-1")
    }

    func testStatusDrivesRespondingAndIgnoresOtherTerminals() async throws {
        let store = makeStore()
        await store.activate()
        let id = try XCTUnwrap(store.terminalID)

        terminal.emit(.statusChanged(TerminalID(), .working))
        await drain()
        XCTAssertFalse(store.isResponding)

        terminal.emit(.statusChanged(id, .working))
        await drain()
        XCTAssertTrue(store.isResponding)
    }

    // MARK: - Çıkış

    func testUnexpectedExitStopsAndRestartResumesSameThread() async throws {
        var state = UIState.defaults
        state.orchestratorCodexThreadID = "kept"
        await config.seed(state)
        let store = makeStore()
        await store.activate()
        let id = try XCTUnwrap(store.terminalID)
        terminal.emit(.codexSessionIDChanged(id, "kept"))
        terminal.emit(.exited(id, code: 1))
        await drain()

        XCTAssertEqual(store.phase, .stopped)
        XCTAssertNotNil(store.errorMessage)

        await store.restart()
        XCTAssertEqual(launcher.requests.map(\.resumeThreadID), ["kept", "kept"])
        XCTAssertEqual(store.phase, .running)
    }

    func testResumeThatExitsBeforeReportingAThreadFallsBackToANewConversation() async throws {
        var state = UIState.defaults
        state.orchestratorCodexThreadID = "gone"
        await config.seed(state)
        let store = makeStore()
        await store.activate()
        let id = try XCTUnwrap(store.terminalID)

        terminal.emit(.exited(id, code: 1))
        await drain()

        XCTAssertEqual(launcher.requests.map(\.resumeThreadID), ["gone", nil])
        XCTAssertEqual(store.phase, .running)
    }

    func testNewConversationKillsQuietlyForgetsWatchListAndIgnoresStoredThread() async throws {
        var state = UIState.defaults
        state.orchestratorCodexThreadID = "old"
        await config.seed(state)
        let watchList = OrchestratorWatchList(config: config)
        let store = makeStore(watchList: watchList)
        watchList.watch(TerminalMeta(id: TerminalID(), name: "api", repoPath: "/p", createdAt: Date(),
                                     claudeSessionID: "c-1", provider: .claude))
        await store.activate()
        let old = try XCTUnwrap(store.terminalID)

        await store.newConversation()
        terminal.emit(.exited(old, code: 0))
        await drain()

        XCTAssertEqual(terminal.killedIDs, [old])
        XCTAssertEqual(launcher.requests.map(\.resumeThreadID), ["old", nil])
        XCTAssertEqual(store.phase, .running, "bilerek kapatılan terminalin çıkışı durdurmaz")
        XCTAssertTrue(watchList.terminalIDs.isEmpty)

        // Yeni thread henüz gelmeden yeniden başlatma eski konuşmaya dönmez.
        await store.restart()
        XCTAssertNil(launcher.requests.last?.resumeThreadID)
    }

    // MARK: - Kurulum

    func testMissingCodexShowsInstallAndInstallerExitStartsCodex() async throws {
        launcher.setCodexMissing(true)
        let store = makeStore()
        await store.activate()
        XCTAssertEqual(store.phase, .codexMissing)
        XCTAssertTrue(terminal.spawnCalls.isEmpty)

        store.installCodex()
        XCTAssertEqual(store.phase, .installing)
        XCTAssertEqual(terminal.spawnCalls.first?.command, OrchestratorStore.installCommand + " && exit")
        let installer = try XCTUnwrap(store.terminalID)

        launcher.setCodexMissing(false)
        terminal.emit(.exited(installer, code: 0))
        await drain()

        XCTAssertEqual(store.phase, .running)
        XCTAssertEqual(launcher.requests.count, 1)
    }

    func testInstallCommandIsTheOfficialScript() {
        XCTAssertEqual(OrchestratorStore.installCommand, "curl -fsSL https://chatgpt.com/codex/install.sh | sh")
    }

    // MARK: - Popup

    func testReplyPastesIntoComposerWithoutSubmitting() async throws {
        let store = makeStore()
        await store.activate()
        let id = try XCTUnwrap(store.terminalID)

        store.typeIntoComposer("Reply to “api”: ")

        XCTAssertEqual(terminal.writtenTexts.first?.id, id)
        XCTAssertEqual(terminal.writtenTexts.first?.text, "\u{1b}[200~Reply to “api”: \u{1b}[201~")
        XCTAssertFalse(terminal.writtenTexts.first?.text.contains("\r") ?? true)
        XCTAssertEqual(terminal.focusCalls.last, id)
    }

    func testShutdownKillsCodexAndStopsServer() async {
        let store = makeStore()
        await store.activate()
        await store.shutdown()
        XCTAssertEqual(terminal.killAllCount, 1)
        XCTAssertEqual(control.stopCount, 1)
        XCTAssertEqual(store.phase, .idle)
    }
}

private struct NoTools: OrchestratorToolHandling {
    func call(name: String, arguments: Data) async -> OrchestratorToolResult { .failure("none") }
}
