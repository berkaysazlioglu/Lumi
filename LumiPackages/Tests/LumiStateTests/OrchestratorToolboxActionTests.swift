import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 123: yazma araçları onaysız, çağrıldıkları an çalışır; geçersiz
/// hedef ya da argüman hiçbir şeye dokunmadan reddedilir.
@MainActor
final class OrchestratorToolboxActionTests: XCTestCase {
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var promptQueue: PromptQueueStore!
    private var trust: FakeClaudeWorkspaceTrust!
    private var toolbox: OrchestratorToolbox!

    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: toasts)
        promptQueue = PromptQueueStore(service: service, toasts: toasts)
        let repos = RepoStore(service: FakeRepoService(repos: [api]))
        await repos.reload()
        let workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(), repos: repos, toasts: toasts
        )
        workspaces.updateSidebarProjects([api.path])
        workspaces.updateRecords([ProjectWorkspace(
            projectPath: api.path, path: "/p/api-wt", name: "api-wt", branch: "feature/login", scm: .git
        )])
        trust = FakeClaudeWorkspaceTrust()
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos,
            transcripts: FakeTerminalTranscripts(), screenText: { _ in "" },
            promptQueue: promptQueue, trust: trust
        )
    }

    @discardableResult
    private func agent(_ name: String, status: TerminalStatus, provider: AgentProvider? = .claude) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: "/p/api-wt", createdAt: Date(),
                                status: status, provider: provider)
        terminals.apply(.spawned(meta))
        return meta
    }

    private func run(_ tool: String, _ args: [String: Any]) async -> OrchestratorToolResult {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return await toolbox.call(name: tool, arguments: data)
    }

    // MARK: - send_to_terminal

    func testMessageToWaitingAgentIsSubmittedImmediatelyWithoutApproval() async {
        let meta = agent("login", status: .waitingUnseen)

        let result = await run(OrchestratorTools.sendToTerminal,
                               ["terminal_id": meta.id.description, "message": "testleri koş"])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(service.writtenTexts.map(\.text), [PromptInjection.encode("testleri koş")])
        XCTAssertEqual(service.writtenTexts.first?.id, meta.id)
        XCTAssertTrue(toolbox.watchList.isWatched(meta), "mesaj gönderilen terminal izlemeye alınır")
        XCTAssertTrue(result.text.contains("now watches"))
    }

    func testBusyAgentGetsTheMessageQueued() async {
        let meta = agent("login", status: .working)

        let result = await run(OrchestratorTools.sendToTerminal,
                               ["terminal_id": meta.id.description, "message": "sonra bunu yap"])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("queued at position 1"))
        XCTAssertTrue(service.writtenTexts.isEmpty, "meşgul ajana doğrudan yazılmaz")
        XCTAssertEqual(promptQueue.prompts(for: meta.id).map(\.text), ["sonra bunu yap"])
    }

    func testAwaitingDecisionCountsAsBusy() async {
        let meta = agent("login", status: .working)
        terminals.apply(.awaitingDecisionChanged(meta.id, true))
        XCTAssertEqual(toolbox.delivery(for: meta), .queued)
        let idle = agent("fresh", status: .idle)
        XCTAssertEqual(toolbox.delivery(for: idle), .now)
    }

    func testNonClaudeTerminalsAndBadArgumentsAreRefused() async {
        let shell = agent("zsh", status: .idle, provider: nil)
        let toShell = await run(OrchestratorTools.sendToTerminal,
                                ["terminal_id": shell.id.description, "message": "rm -rf"])
        XCTAssertTrue(toShell.isError)
        let codex = agent("codex", status: .waitingSeen, provider: .codex)
        let toCodex = await run(OrchestratorTools.sendToTerminal,
                                ["terminal_id": codex.id.description, "message": "selam"])
        XCTAssertTrue(toCodex.text.contains("not a Claude Code terminal"), toCodex.text)
        let empty = await run(OrchestratorTools.sendToTerminal,
                              ["terminal_id": shell.id.description, "message": "  "])
        XCTAssertTrue(empty.isError)
        XCTAssertTrue(service.writtenTexts.isEmpty)
    }

    // MARK: - start_terminal

    func testStartSpawnsQuotedPromptAndTrustsWorkspace() async {
        let result = await run(OrchestratorTools.startTerminal, ["path": "/p/api-wt", "prompt": "it's a test"])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(service.spawnCalls.first?.repoPath, "/p/api-wt")
        XCTAssertEqual(service.spawnCalls.first?.command, "claude " + shellQuoted("it's a test"))
        XCTAssertEqual(trust.trusted, ["/p/api-wt"])
        let spawned = try? XCTUnwrap(service.spawnedMetas.first)
        XCTAssertTrue(result.text.contains(spawned?.id.description ?? "-"))
        XCTAssertEqual(toolbox.watchList.terminalIDs, spawned.map { [$0.id] }, "açılan terminal izlenir")
    }

    func testStartWithoutPromptUsesBareClaude() async {
        let result = await run(OrchestratorTools.startTerminal, ["path": "/p/api"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(service.spawnCalls.first?.command, "claude")
    }

    func testTrailingSlashInCheckoutPathIsTolerated() async {
        let result = await run(OrchestratorTools.startTerminal, ["path": "/p/api-wt/"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(service.spawnCalls.first?.repoPath, "/p/api-wt")
    }

    func testUnknownPathIsRefused() async {
        let result = await run(OrchestratorTools.startTerminal, ["path": "/etc"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(service.spawnCalls.isEmpty)
    }

    func testAskProjectIsNoLongerATool() async {
        let result = await run("ask_project", ["path": "/p/api", "question": "özetle"])
        XCTAssertTrue(result.isError, "orchestrator yalnız terminal açar ve mesaj gönderir")
        XCTAssertFalse(OrchestratorTools.specs.map(\.name).contains("ask_project"))
    }
}
