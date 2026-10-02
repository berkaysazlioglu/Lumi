import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 103 Faz 2: orchestrator'ın okuma araçları canlı store durumunu okur.
@MainActor
final class OrchestratorToolboxTests: XCTestCase {
    private var terminals: TerminalListStore!
    private var workspaces: ProjectWorkspaceStore!
    private var transcripts: FakeTerminalTranscripts!
    private var screens: [TerminalID: String] = [:]
    private var toolbox: OrchestratorToolbox!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)
    private let ios = Repo(name: "ios", path: "/p/ios", isGitRepo: true, source: .standalone)

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        terminals = TerminalListStore(service: FakeTerminalService(), toasts: toasts)
        let repoService = FakeRepoService(repos: [api, ios])
        let repos = RepoStore(service: repoService)
        await repos.reload()
        workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(), repos: repos, toasts: toasts
        )
        workspaces.updateSidebarProjects([api.path, ios.path])
        workspaces.updateRecords([ProjectWorkspace(
            projectPath: api.path, path: "/p/api-wt", name: "api-wt", branch: "feature/login", scm: .git
        )])
        transcripts = FakeTerminalTranscripts()
        screens = [:]
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos, transcripts: transcripts,
            screenText: { [unowned self] id in self.screens[id] ?? "" },
            now: { [now] in now }
        )
    }

    @discardableResult
    private func terminal(
        _ name: String, repo: String, provider: AgentProvider? = .claude,
        status: TerminalStatus = .idle, sessionID: String? = nil, activeAgo: TimeInterval = 60
    ) -> TerminalMeta {
        let meta = TerminalMeta(
            id: TerminalID(), name: name, repoPath: repo, createdAt: now.addingTimeInterval(-activeAgo),
            status: status, claudeSessionID: sessionID, provider: provider
        )
        terminals.apply(.spawned(meta))
        return meta
    }

    private func call(_ name: String, _ args: [String: Any] = [:]) async -> OrchestratorToolResult {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return await toolbox.call(name: name, arguments: data)
    }

    private func jsonList(_ result: OrchestratorToolResult, key: String) throws -> [[String: Any]] {
        XCTAssertFalse(result.isError, result.text)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])
        return try XCTUnwrap(object[key] as? [[String: Any]])
    }

    // MARK: - list_terminals

    func testListTerminalsCarriesLocationStatusAndRecencyOrder() async throws {
        let old = terminal("refactor", repo: api.path, status: .waitingUnseen, activeAgo: 3_600)
        let recent = terminal("login", repo: "/p/api-wt", status: .working, activeAgo: 30)

        let rows = try jsonList(await call(OrchestratorTools.listTerminals), key: "terminals")

        XCTAssertEqual(rows.map { $0["id"] as? String }, [recent.id.description, old.id.description])
        XCTAssertEqual(rows[0]["checkout"] as? String, "api-wt")
        XCTAssertEqual(rows[0]["branch"] as? String, "feature/login")
        XCTAssertEqual(rows[0]["status"] as? String, "working")
        XCTAssertEqual(rows[0]["lastActivity"] as? String, "just now")
        XCTAssertEqual(rows[1]["project"] as? String, "api")
        XCTAssertEqual(rows[1]["status"] as? String, "needs-attention")
        XCTAssertEqual(rows[1]["lastActivity"] as? String, "1h ago")
    }

    func testAwaitingDecisionOverridesStatus() async throws {
        let blocked = terminal("blocked", repo: ios.path, status: .working)
        terminals.apply(.awaitingDecisionChanged(blocked.id, true))

        let rows = try jsonList(await call(OrchestratorTools.listTerminals), key: "terminals")
        XCTAssertEqual(rows.first?["status"] as? String, "awaiting-decision")
    }

    func testQueryFiltersByProjectBranchOrTitle() async throws {
        terminal("refactor", repo: api.path)
        let mobile = terminal("crash fix", repo: ios.path)
        let branch = terminal("login", repo: "/p/api-wt")

        let byProject = try jsonList(await call(OrchestratorTools.listTerminals, ["query": "IOS"]), key: "terminals")
        XCTAssertEqual(byProject.map { $0["id"] as? String }, [mobile.id.description])
        let byBranch = try jsonList(await call(OrchestratorTools.listTerminals, ["query": "feature/log"]), key: "terminals")
        XCTAssertEqual(byBranch.map { $0["id"] as? String }, [branch.id.description])

        let none = await call(OrchestratorTools.listTerminals, ["query": "android"])
        XCTAssertFalse(none.isError)
        XCTAssertTrue(none.text.contains("No terminal matches"))
    }

    // MARK: - list_projects

    func testListProjectsMirrorsTheProjectsPanelTree() async throws {
        let agent = terminal("login", repo: "/p/api-wt")

        let projects = try jsonList(await call(OrchestratorTools.listProjects), key: "projects")

        XCTAssertEqual(projects.map { $0["name"] as? String }, ["api", "ios"])
        let checkouts = try XCTUnwrap(projects[0]["checkouts"] as? [[String: Any]])
        XCTAssertEqual(checkouts.map { $0["title"] as? String }, ["main", "api-wt"])
        let agents = try XCTUnwrap(checkouts[1]["terminals"] as? [[String: Any]])
        XCTAssertEqual(agents.first?["id"] as? String, agent.id.description)
    }

    // MARK: - read_terminal

    func testReadClaudeTerminalReturnsTranscriptTail() async {
        let meta = terminal("refactor", repo: api.path, status: .waitingUnseen, sessionID: "sess-1")
        transcripts.stub(sessionID: "sess-1", cwd: api.path, messages: [
            message("u1", .user, [.text("eski istek", presentation: nil)]),
            message("a1", .assistant, [.text("eski cevap", presentation: nil)]),
            message("u2", .user, [.text("testleri düzelt", presentation: nil)]),
            message("a2", .assistant, [.toolCall(name: "Bash", inputPreview: "swift test", state: nil)]),
            message("r2", .user, [.toolResult(output: "2 failed", isError: false)]),
            message("a3", .assistant, [.text("İki testi düzelttim. Commit atayım mı?", presentation: nil)]),
        ])

        let result = await call(OrchestratorTools.readTerminal, ["terminal_id": meta.id.description, "limit": 2])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("needs-attention"))
        XCTAssertTrue(result.text.contains("[user] testleri düzelt"))
        XCTAssertTrue(result.text.contains("· tool Bash swift test"), "aradaki araç satırları korunur")
        XCTAssertTrue(result.text.contains("· result: 2 failed"))
        XCTAssertTrue(result.text.contains("[assistant] İki testi düzelttim. Commit atayım mı?"))
        XCTAssertFalse(result.text.contains("eski"), "limit metinli mesaj sayar")
    }

    func testReadNonClaudeTerminalFallsBackToScreenTail() async {
        let meta = terminal("build", repo: ios.path, provider: nil)
        screens[meta.id] = "line 1\nline 2   \n\n\n"

        let result = await call(OrchestratorTools.readTerminal, ["terminal_id": meta.id.description])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.hasSuffix("Last screen lines:\nline 1\nline 2"))
    }

    func testTerminalIDAcceptsUniquePrefixAndRejectsUnknown() async {
        let meta = terminal("build", repo: ios.path, provider: nil)
        screens[meta.id] = "ok"
        let prefix = String(meta.id.description.prefix(8)).lowercased()

        let byPrefix = await call(OrchestratorTools.readTerminal, ["terminal_id": prefix])
        XCTAssertFalse(byPrefix.isError, byPrefix.text)

        let unknown = await call(OrchestratorTools.readTerminal, ["terminal_id": "ffffffff-nope"])
        XCTAssertTrue(unknown.isError)
        let tooShort = await call(OrchestratorTools.readTerminal, ["terminal_id": "ab"])
        XCTAssertTrue(tooShort.isError)
        let missing = await call(OrchestratorTools.readTerminal)
        XCTAssertTrue(missing.isError)
    }

    func testUnknownToolIsAnError() async {
        let result = await call("delete_everything")
        XCTAssertTrue(result.isError)
    }

    func testLimitIsClamped() {
        XCTAssertEqual(OrchestratorToolbox.clampedLimit(nil), OrchestratorTools.defaultReadLimit)
        XCTAssertEqual(OrchestratorToolbox.clampedLimit(0), 1)
        XCTAssertEqual(OrchestratorToolbox.clampedLimit(999), OrchestratorTools.maxReadLimit)
    }

    private func message(_ id: String, _ role: ChatRole, _ blocks: [ChatBlock]) -> ChatMessage {
        ChatMessage(id: id, role: role, blocks: blocks, timestampMs: nil, turnId: id)
    }
}
