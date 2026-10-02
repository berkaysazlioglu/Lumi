import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 103 Faz 3: yazma araçları onaysız hiçbir şeye dokunmaz; onaydan
/// sonra hedefi yeniden çözer.
@MainActor
final class OrchestratorToolboxActionTests: XCTestCase {
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var promptQueue: PromptQueueStore!
    private var approvals: OrchestratorApprovals!
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
        approvals = OrchestratorApprovals()
        trust = FakeClaudeWorkspaceTrust()
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos,
            transcripts: FakeTerminalTranscripts(), screenText: { _ in "" },
            approvals: approvals, promptQueue: promptQueue, trust: trust
        )
    }

    @discardableResult
    private func agent(_ name: String, status: TerminalStatus, provider: AgentProvider? = .claude) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: "/p/api-wt", createdAt: Date(),
                                status: status, provider: provider)
        terminals.apply(.spawned(meta))
        return meta
    }

    /// Aracı başlatır, onay kartı gelince `answer` ile cevaplar.
    private func run(
        _ tool: String, _ args: [String: Any],
        answer: ((OrchestratorApprovals, OrchestratorApprovalRequest) -> Void)?
    ) async -> (OrchestratorToolResult, OrchestratorApprovalRequest?) {
        let data = try! JSONSerialization.data(withJSONObject: args)
        let task = Task { await toolbox.call(name: tool, arguments: data) }
        guard let answer else { return (await task.value, nil) }
        var card: OrchestratorApprovalRequest?
        while card == nil {
            card = approvals.pending.first
            await Task.yield()
        }
        answer(approvals, card!)
        return (await task.value, card)
    }

    private let approve: (OrchestratorApprovals, OrchestratorApprovalRequest) -> Void = { $0.approve($1.id) }
    private let reject: (OrchestratorApprovals, OrchestratorApprovalRequest) -> Void = { $0.reject($1.id) }

    // MARK: - send_to_terminal

    func testApprovedMessageToWaitingAgentIsSubmittedImmediately() async {
        let meta = agent("login", status: .waitingUnseen)

        let (result, card) = await run(OrchestratorTools.sendToTerminal,
                                       ["terminal_id": meta.id.description, "message": "testleri koş"], answer: approve)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(card?.title, "Send to “login”")
        XCTAssertEqual(card?.target, "api · api-wt · feature/login · needs-attention")
        XCTAssertEqual(card?.body, "testleri koş")
        XCTAssertNil(card?.note)
        XCTAssertEqual(service.writtenTexts.map(\.text), [PromptInjection.encode("testleri koş")])
        XCTAssertEqual(service.writtenTexts.first?.id, meta.id)
        XCTAssertTrue(toolbox.watchList.isWatched(meta), "mesaj gönderilen terminal izlemeye alınır")
        XCTAssertTrue(result.text.contains("now watches"))
    }

    func testBusyAgentGetsTheMessageQueued() async {
        let meta = agent("login", status: .working)

        let (result, card) = await run(OrchestratorTools.sendToTerminal,
                                       ["terminal_id": meta.id.description, "message": "sonra bunu yap"], answer: approve)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertNotNil(card?.note, "kart kuyruğa gideceğini söyler")
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

    func testRejectedMessageIsNeverWritten() async {
        let meta = agent("login", status: .waitingSeen)

        let (result, _) = await run(OrchestratorTools.sendToTerminal,
                                    ["terminal_id": meta.id.description, "message": "x"], answer: reject)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("declined"))
        XCTAssertTrue(service.writtenTexts.isEmpty)
        XCTAssertTrue(promptQueue.prompts(for: meta.id).isEmpty)
        XCTAssertFalse(toolbox.watchList.isWatched(meta), "reddedilen eylem izleme başlatmaz")
    }

    func testTerminalClosedWhileWaitingForApprovalFails() async {
        let meta = agent("login", status: .waitingSeen)

        let (result, _) = await run(OrchestratorTools.sendToTerminal,
                                    ["terminal_id": meta.id.description, "message": "x"]) { approvals, card in
            self.terminals.apply(.exited(meta.id, code: 0))
            approvals.approve(card.id)
        }

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("closed"))
        XCTAssertTrue(service.writtenTexts.isEmpty)
    }

    func testNonClaudeTerminalsAndBadArgumentsAreRefusedWithoutAsking() async {
        let shell = agent("zsh", status: .idle, provider: nil)
        let (toShell, _) = await run(OrchestratorTools.sendToTerminal,
                                     ["terminal_id": shell.id.description, "message": "rm -rf"], answer: nil)
        XCTAssertTrue(toShell.isError)
        let codex = agent("codex", status: .waitingSeen, provider: .codex)
        let (toCodex, _) = await run(OrchestratorTools.sendToTerminal,
                                     ["terminal_id": codex.id.description, "message": "selam"], answer: nil)
        XCTAssertTrue(toCodex.text.contains("not a Claude Code terminal"), toCodex.text)
        let (empty, _) = await run(OrchestratorTools.sendToTerminal,
                                   ["terminal_id": shell.id.description, "message": "  "], answer: nil)
        XCTAssertTrue(empty.isError)
        XCTAssertTrue(approvals.pending.isEmpty, "geçersiz istek onaya hiç gelmez")
    }

    // MARK: - start_terminal

    func testApprovedStartSpawnsQuotedPromptAndTrustsWorkspace() async {
        let (result, card) = await run(OrchestratorTools.startTerminal,
                                       ["path": "/p/api-wt", "prompt": "it's a test"], answer: approve)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(card?.title, "Start Claude")
        XCTAssertEqual(card?.target, "api · api-wt · feature/login — /p/api-wt")
        XCTAssertEqual(service.spawnCalls.first?.repoPath, "/p/api-wt")
        XCTAssertEqual(service.spawnCalls.first?.command, "claude " + shellQuoted("it's a test"))
        XCTAssertEqual(trust.trusted, ["/p/api-wt"])
        let spawned = try? XCTUnwrap(service.spawnedMetas.first)
        XCTAssertTrue(result.text.contains(spawned?.id.description ?? "-"))
        XCTAssertEqual(toolbox.watchList.terminalIDs, spawned.map { [$0.id] }, "açılan terminal izlenir")
    }

    func testStartWithoutPromptUsesBareClaude() async {
        let (result, _) = await run(OrchestratorTools.startTerminal, ["path": "/p/api"], answer: approve)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(service.spawnCalls.first?.command, "claude")
    }

    func testRejectedStartSpawnsNothing() async {
        let (result, _) = await run(OrchestratorTools.startTerminal, ["path": "/p/api"], answer: reject)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(service.spawnCalls.isEmpty)
    }

    func testUnknownPathIsRefusedWithoutAsking() async {
        let (path, _) = await run(OrchestratorTools.startTerminal, ["path": "/etc"], answer: nil)
        XCTAssertTrue(path.isError)
        XCTAssertTrue(approvals.pending.isEmpty)
        XCTAssertTrue(service.spawnCalls.isEmpty)
    }
}
