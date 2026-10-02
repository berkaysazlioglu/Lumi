import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 104: yalnız izlenen terminaller raporlanır; sonradan izlemeye
/// alınanın oturumu bir ajana özetletilir ve liste oturum kimliğiyle kalıcıdır.
@MainActor
final class OrchestratorWatchTests: XCTestCase {
    private var terminals: TerminalListStore!
    private var transcripts: FakeTerminalTranscripts!
    private var summarizer: FakeTerminalDigestSummarizer!
    private var config: FakeConfigService!
    private var watchList: OrchestratorWatchList!
    private var toolbox: OrchestratorToolbox!

    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        terminals = TerminalListStore(service: FakeTerminalService(), toasts: toasts)
        let repos = RepoStore(service: FakeRepoService(repos: [api]))
        await repos.reload()
        let workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(), repos: repos, toasts: toasts
        )
        workspaces.updateSidebarProjects([api.path])
        transcripts = FakeTerminalTranscripts()
        summarizer = FakeTerminalDigestSummarizer()
        config = FakeConfigService()
        watchList = OrchestratorWatchList(config: config)
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos,
            transcripts: transcripts, screenText: { _ in "" },
            watchList: watchList, summarizer: summarizer
        )
    }

    @discardableResult
    private func agent(_ session: String?, provider: AgentProvider = .claude) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: "refactor", repoPath: api.path, createdAt: Date(),
                                status: .waitingSeen, claudeSessionID: session, provider: provider)
        terminals.apply(.spawned(meta))
        return meta
    }

    private func call(_ name: String, _ meta: TerminalMeta) async -> OrchestratorToolResult {
        let data = try! JSONSerialization.data(withJSONObject: ["terminal_id": meta.id.description])
        return await toolbox.call(name: name, arguments: data)
    }

    private func text(_ id: String, _ role: ChatRole, _ value: String) -> ChatMessage {
        ChatMessage(id: id, role: role, blocks: [.text(value, presentation: nil)], timestampMs: nil, turnId: id)
    }

    // MARK: - watch_terminal / unwatch_terminal

    func testWatchSummarizesTheSessionSoFarWithAHelperAgent() async {
        let meta = agent("s-1")
        transcripts.stub(sessionID: "s-1", cwd: api.path, messages: [
            text("u", .user, "login akışını yaz"),
            text("a", .assistant, "LoginView eklendi. Testleri de yazayım mı?"),
        ])
        summarizer.stub(.success(TerminalDigest(summary: "Login akışını yazdı.", needsUser: true)))

        let result = await call(OrchestratorTools.watchTerminal, meta)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("Now watching \"refactor\""))
        XCTAssertTrue(result.text.contains("Login akışını yazdı."))
        XCTAssertTrue(result.text.contains("waiting on the user"))
        XCTAssertEqual(summarizer.sessionRequests.count, 1)
        XCTAssertTrue(summarizer.sessionRequests.first?.contains("[user] login akışını yaz") == true)
        XCTAssertTrue(watchList.isWatched(meta))

        let again = await call(OrchestratorTools.watchTerminal, meta)
        XCTAssertTrue(again.text.contains("Already watching"))
        XCTAssertEqual(summarizer.sessionRequests.count, 1, "ikinci kez özet üretilmez")
    }

    func testWatchFallsBackToLastMessageAndSkipsEmptySessions() async {
        let fresh = agent("s-empty")
        let empty = await call(OrchestratorTools.watchTerminal, fresh)
        XCTAssertTrue(empty.text.contains("(no conversation yet)"))
        XCTAssertTrue(summarizer.sessionRequests.isEmpty, "boş oturum ajana gitmez")

        let meta = agent("s-2")
        transcripts.stub(sessionID: "s-2", cwd: api.path, messages: [text("a", .assistant, "Build yeşil.")])
        summarizer.stub(.failure(.digestFailed(detail: "timeout")))
        let fallback = await call(OrchestratorTools.watchTerminal, meta)
        XCTAssertTrue(fallback.text.contains("Summary unavailable"), fallback.text)
        XCTAssertTrue(fallback.text.contains("Build yeşil."))
    }

    func testUnwatchAndNonClaudeTerminals() async {
        let meta = agent("s-1")
        watchList.watch(meta)
        let stopped = await call(OrchestratorTools.unwatchTerminal, meta)
        XCTAssertTrue(stopped.text.contains("Stopped watching"))
        XCTAssertFalse(watchList.isWatched(meta))
        let notWatched = await call(OrchestratorTools.unwatchTerminal, meta)
        XCTAssertTrue(notWatched.text.contains("was not being watched"))

        let codex = agent(nil, provider: .codex)
        let refused = await call(OrchestratorTools.watchTerminal, codex)
        XCTAssertTrue(refused.isError)
        XCTAssertFalse(watchList.isWatched(codex))
    }

    func testListTerminalsMarksWatched() async throws {
        let watched = agent("s-1")
        agent("s-2")
        watchList.watch(watched)

        let data = try JSONSerialization.data(withJSONObject: [String: Any]())
        let result = await toolbox.call(name: OrchestratorTools.listTerminals, arguments: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])
        let rows = try XCTUnwrap(object["terminals"] as? [[String: Any]])
        let flags = Dictionary(uniqueKeysWithValues: rows.map { ($0["id"] as? String ?? "", $0["watched"] as? Bool) })
        XCTAssertEqual(flags[watched.id.description], true)
        XCTAssertEqual(flags.values.filter { $0 == true }.count, 1)
    }

    // MARK: - Kalıcılık

    func testListPersistsSessionIDsAndReattachesAfterRelaunch() async {
        let meta = agent("s-1")
        watchList.watch(meta)
        watchList.sessionChanged(meta.id, to: "s-1b")
        await watchList.flush()
        let saved = await config.uiState().orchestratorWatchedSessions
        XCTAssertEqual(saved, ["s-1b"], "/clear sonrası yeni oturum kimliği yazılır")

        // Yeniden açılış: terminal kimliği yeni, oturum aynı.
        let relaunched = OrchestratorWatchList(config: config)
        let resumed = TerminalMeta(id: TerminalID(), name: "refactor", repoPath: api.path, createdAt: Date(),
                                   claudeSessionID: "s-1b", provider: .claude)
        await relaunched.load(matching: [resumed])
        XCTAssertEqual(relaunched.terminalIDs, [resumed.id])
    }

    func testClosingATerminalDoesNotRewriteTheList() async {
        let meta = agent("s-1")
        watchList.watch(meta)
        await watchList.flush()
        watchList.forget(meta.id)
        await watchList.flush()

        XCTAssertFalse(watchList.isWatched(meta))
        let saved = await config.uiState().orchestratorWatchedSessions
        XCTAssertEqual(saved, ["s-1"], "quit'te kapanan terminaller listeyi silmez")
    }
}
