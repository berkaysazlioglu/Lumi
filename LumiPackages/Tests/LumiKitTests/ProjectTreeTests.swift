import Foundation
import Testing
@testable import LumiKit

/// Karar 91/103: Projects ağacının tek kaynağı (telefon + orchestrator).
@Suite struct ProjectTreeTests {
    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)
    private let docs = Repo(name: "docs", path: "/p/docs", isGitRepo: false, source: .standalone)

    @Test func favoritesKeepOrderAndCheckoutsCarryTerminalsByRecency() {
        let base = Date(timeIntervalSince1970: 0)
        let older = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/p/api", createdAt: base)
        let newer = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/p/api", createdAt: base.addingTimeInterval(10))
        let elsewhere = TerminalMeta(id: TerminalID(), name: "c", repoPath: "/p/api-wt", createdAt: base)
        let workspace = ProjectWorkspace(projectPath: "/p/api", path: "/p/api-wt", name: "api-wt", branch: "feat", scm: .git)

        let tree = ProjectTree.build(
            favoritePaths: ["/p/docs", "/p/api", "/p/missing"],
            repos: [api, docs],
            workspaces: [workspace],
            terminals: [older, newer, elsewhere]
        )

        #expect(tree.map(\.name) == ["docs", "api"], "repo listesinde olmayan favori atlanır")
        #expect(tree[0].checkouts.map(\.scm) == ["none"])
        let checkouts = tree[1].checkouts
        #expect(checkouts.map(\.kind) == [.original, .workspace])
        #expect(checkouts[0].title == ProjectTree.originalTitle && checkouts[0].branch == nil)
        #expect(checkouts[0].terminalIDs == [newer.id, older.id])
        #expect(checkouts[1].branch == "feat" && checkouts[1].terminalIDs == [elsewhere.id])
    }
}
