import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiState

/// Gerçek task ajanı koşucusu (karar 137, Faz 3): komut biçimi, workspace,
/// terminal durumunun eşlenmesi, teslim ve yeniden bağlanma.
@MainActor
final class LiveTaskAgentRunnerTests: XCTestCase {
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var tools: FakeTaskAgentTools!
    private var trusted: [String] = []
    private var events: [TaskAgentEvent] = []
    private let key = TaskKey(source: TaskSourceID("s"), id: "DEMO-1")

    override func setUp() async throws {
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        tools = FakeTaskAgentTools()
        trusted = []
        events = []
    }

    private func runner(createWorkspace: LiveTaskAgentRunner.WorkspaceCreator? = nil) -> LiveTaskAgentRunner {
        LiveTaskAgentRunner(
            terminals: terminals,
            tools: tools,
            createWorkspace: createWorkspace ?? { _, _ in XCTFail("workspace not expected"); return "" },
            trust: { [weak self] in self?.trusted.append($0) },
            reattachWait: .milliseconds(300)
        )
    }

    private func request(_ checkout: TaskCheckoutChoice = .existing(path: "/repo"), model: ClaudeModelAlias? = .opus) -> TaskAgentRequest {
        TaskAgentRequest(
            task: key, taskTitle: "Board drag", checkout: checkout,
            agent: TaskAgentChoice(model: model), prompt: "Work on it's task", details: "DEMO-1: Board drag"
        )
    }

    /// Akışı arka planda toplar.
    private func collect(_ stream: AsyncStream<TaskAgentEvent>) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in stream { self.events.append(event) }
        }
    }

    /// Koşul 2 sn içinde sağlanmalı (actor geçişleri + yeniden bağlanma yoklaması).
    private func waitFor(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "condition not met; events: \(events)", file: file, line: line)
    }

    private var spawned: TerminalMeta? { service.spawnedMetas.first }

    // MARK: - Başlatma

    func testStartsVisibleClaudeTerminalWithPromptFirstAndScopedTools() async {
        let task = collect(runner().start(request()))
        await waitFor { self.spawned != nil }

        let call = service.spawnCalls[0]
        XCTAssertEqual(call.repoPath, "/repo")
        XCTAssertEqual(call.task, "DEMO-1 · Board drag")
        XCTAssertEqual(
            call.command,
            "claude 'Work on it'\\''s task' --model opus --mcp-config '/tmp/mcp-0.json' --allowedTools mcp__lumi__get_task,mcp__lumi__submit_for_review"
        )
        XCTAssertEqual(trusted, ["/repo"])
        let registered = await tools.registered
        XCTAssertEqual(registered.map(\.details), ["DEMO-1: Board drag"])
        XCTAssertEqual(terminals.cardBadges[spawned!.id], "DEMO-1")
        await waitFor { self.events.contains(.started(self.spawned!.id, sessionID: self.spawned!.claudeSessionID)) }
        task.cancel()
    }

    func testDefaultModelOmitsModelFlag() {
        let command = LiveTaskAgentRunner.command(for: request(model: nil), mcpConfig: "/x.json")
        XCTAssertFalse(command.contains("--model"))
        XCTAssertTrue(command.hasPrefix("claude 'Work on it'\\''s task' --mcp-config"))
    }

    func testNewWorkspaceIsCreatedBeforeTheTerminal() async {
        var created: [(String, String)] = []
        let runner = runner { project, branch in
            created.append((project, branch))
            return "/ws/demo-1"
        }
        let task = collect(runner.start(request(.newWorkspace(projectPath: "/repo", branch: "task/demo-1"))))
        await waitFor { self.spawned != nil }

        XCTAssertEqual(created.map(\.1), ["task/demo-1"])
        XCTAssertEqual(service.spawnCalls[0].repoPath, "/ws/demo-1")
        XCTAssertEqual(trusted, ["/ws/demo-1"])
        XCTAssertTrue(events.contains(.checkout("/ws/demo-1")))
        task.cancel()
    }

    func testWorkspaceFailureStopsBeforeSpawning() async {
        struct Boom: LocalizedError { var errorDescription: String? { "branch exists" } }
        let task = collect(runner { _, _ in throw Boom() }.start(request(.newWorkspace(projectPath: "/repo", branch: "b"))))
        await task.value
        XCTAssertEqual(events, [.failed("Couldn't create the workspace: branch exists")])
        XCTAssertTrue(service.spawnCalls.isEmpty)
    }

    func testToolServerFailureStopsBeforeSpawning() async {
        await tools.setFails(true)
        let task = collect(runner().start(request()))
        await task.value
        guard case .failed(let message) = events.last else { return XCTFail("\(events)") }
        XCTAssertTrue(message.contains("task tools"))
        XCTAssertTrue(service.spawnCalls.isEmpty)
    }

    // MARK: - Durum

    func testStateFollowsTheTerminalUntilItCloses() async {
        let task = collect(runner().start(request()))
        await waitFor { self.spawned != nil }
        let id = spawned!.id
        await waitFor { self.events.contains(.state(.starting)) }

        terminals.apply(.spawned(spawned!))
        terminals.apply(.statusChanged(id, .working))
        await waitFor { self.events.last == .state(.working) }
        terminals.apply(.awaitingDecisionChanged(id, true))
        await waitFor { self.events.last == .state(.needsInput) }
        terminals.apply(.awaitingDecisionChanged(id, false))
        terminals.apply(.statusChanged(id, .waitingUnseen))
        await waitFor { self.events.last == .state(.idle) }
        terminals.apply(.exited(id, code: 0))
        await waitFor { self.events.last == .state(.exited) }
        await task.value

        try? await Task.sleep(for: .milliseconds(100))
        let unregistered = await tools.unregistered
        XCTAssertEqual(unregistered.map(\.token), ["tok-0"], "terminal kapanınca MCP oturumu düşer")
    }

    func testSubmitMovesToSubmittedAndOnlyExitOverridesIt() async {
        let task = collect(runner().start(request()))
        await waitFor { self.spawned != nil }
        let id = spawned!.id
        terminals.apply(.spawned(spawned!))
        terminals.apply(.statusChanged(id, .working))
        await waitFor { self.events.last == .state(.working) }

        let reply = await tools.submit(token: "tok-0", summary: "Done, tests pass")
        XCTAssertTrue(reply?.contains("In Review") == true)
        await waitFor { self.events.last == .state(.submitted(summary: "Done, tests pass")) }

        terminals.apply(.statusChanged(id, .waitingUnseen))
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(events.last, .state(.submitted(summary: "Done, tests pass")), "teslim çipi ezilmez")

        terminals.apply(.exited(id, code: 0))
        await waitFor { self.events.last == .state(.exited) }
        task.cancel()
    }

    func testStateMapping() {
        let meta = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/r", createdAt: Date(), status: .idle, provider: .claude)
        XCTAssertEqual(LiveTaskAgentRunner.state(meta: nil, isAwaitingDecision: false, hasStarted: true), .exited)
        XCTAssertEqual(LiveTaskAgentRunner.state(meta: meta, isAwaitingDecision: false, hasStarted: false), .starting)
        XCTAssertEqual(LiveTaskAgentRunner.state(meta: meta, isAwaitingDecision: false, hasStarted: true), .idle)
        var shell = meta
        shell.provider = nil
        XCTAssertEqual(LiveTaskAgentRunner.state(meta: shell, isAwaitingDecision: false, hasStarted: true), .exited, "claude çıktı")
        XCTAssertEqual(LiveTaskAgentRunner.state(meta: meta, isAwaitingDecision: true, hasStarted: false), .needsInput)
    }

    // MARK: - Yeniden bağlanma

    func testReattachFindsResumedTerminalBySession() async {
        let meta = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/r", createdAt: Date(), status: .working, claudeSessionID: "s1")
        let task = collect(runner().reattach(sessionID: "s1", task: key))
        terminals.apply(.spawned(meta))
        await waitFor { self.events.contains(.started(meta.id, sessionID: "s1")) }
        await waitFor { self.events.last == .state(.working) }
        XCTAssertEqual(terminals.cardBadges[meta.id], "DEMO-1")
        task.cancel()
    }

    func testReattachGivesUpWhenTheTerminalNeverComes() async {
        let task = collect(runner().reattach(sessionID: "missing", task: key))
        await task.value
        XCTAssertTrue(events.isEmpty)
    }
}
