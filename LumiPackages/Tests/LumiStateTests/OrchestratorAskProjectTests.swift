import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 103 Faz 5: `ask_project` doğrulaması ve sonucu.
@MainActor
final class OrchestratorAskProjectTests: XCTestCase {
    private var asker: FakeProjectQuestionAnswerer!
    private var approvals: OrchestratorApprovals!
    private var toolbox: OrchestratorToolbox!

    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        let terminals = TerminalListStore(service: FakeTerminalService(), toasts: toasts)
        let repos = RepoStore(service: FakeRepoService(repos: [api]))
        await repos.reload()
        let workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(), repos: repos, toasts: toasts
        )
        workspaces.updateSidebarProjects([api.path])
        workspaces.updateRecords([ProjectWorkspace(
            projectPath: api.path, path: "/p/api-wt", name: "api-wt", branch: "feature/login", scm: .git
        )])
        asker = FakeProjectQuestionAnswerer()
        approvals = OrchestratorApprovals()
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos,
            transcripts: FakeTerminalTranscripts(), screenText: { _ in "" },
            approvals: approvals, projectAsker: asker
        )
    }

    private func call(_ args: [String: Any]) async -> OrchestratorToolResult {
        await toolbox.call(name: OrchestratorTools.askProject, arguments: try! JSONSerialization.data(withJSONObject: args))
    }

    func testAnswerComesBackWithSourceAndCostFooterWithoutApproval() async {
        asker.stub(.success(ProjectAnswer(text: "Login akışı `Auth/` altında.", costUSD: 0.083, durationSeconds: 33.6)))

        let result = await call(["path": "/p/api-wt", "question": " login nerede? "])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(result.text, "Login akışı `Auth/` altında.\n\n(ask_project · api · api-wt · $0.08 · 34 s)")
        XCTAssertEqual(asker.questions.map(\.projectPath), ["/p/api-wt"])
        XCTAssertEqual(asker.questions.first?.question, "login nerede?")
        XCTAssertTrue(approvals.pending.isEmpty, "salt-okunur — onay istemez")
    }

    func testUnknownPathAndEmptyQuestionAreRefused() async {
        let unknown = await call(["path": "/etc", "question": "q"])
        XCTAssertTrue(unknown.isError)
        let empty = await call(["path": "/p/api", "question": "  "])
        XCTAssertTrue(empty.isError)
        XCTAssertTrue(asker.questions.isEmpty)
    }

    func testAskerFailureIsReportedAsToolError() async {
        asker.stub(.failure(.projectQuestionFailed(detail: "error_max_budget_usd")))
        let result = await call(["path": "/p/api", "question": "özetle"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("error_max_budget_usd"))
    }
}
