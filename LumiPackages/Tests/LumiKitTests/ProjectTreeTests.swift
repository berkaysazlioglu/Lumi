import Foundation
import Testing
@testable import LumiKit

/// Karar 91/114: Projects ağacının tek kaynağı (telefon + orchestrator).
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

    @Test func managedWorkspaceFavoriteStaysUnderItsProject() {
        let workspace = ProjectWorkspace(projectPath: "/p/api", path: "/p/api-wt", name: "api-wt", branch: "feat", scm: .git)
        let wtRepo = Repo(name: "api-wt", path: "/p/api-wt", isGitRepo: true, source: .standalone)

        let tree = ProjectTree.build(
            favoritePaths: ["/p/api", "/p/api-wt"], repos: [api, wtRepo], workspaces: [workspace], terminals: []
        )

        #expect(tree.map(\.path) == ["/p/api"], "Projects paneli (addedProjects) paritesi")
        #expect(tree[0].checkouts.map(\.path) == ["/p/api", "/p/api-wt"])
    }

    /// Karar 108/114: ağaçtaki hiçbir checkout'a ait olmayan terminaller
    /// `Other`'da dizinlerine göre, etiket sırasıyla durur.
    @Test func snapshotGroupsLooseTerminalsByFolder() {
        let home = "/Users/me"
        let owned = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/p/api/", createdAt: Date())
        let desktop = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/Users/me/Desktop", createdAt: Date())
        let tmp = TerminalMeta(id: TerminalID(), name: "c", repoPath: "/tmp/x", createdAt: Date())
        let homeOne = TerminalMeta(id: TerminalID(), name: "d", repoPath: "/Users/me", createdAt: Date())
        let homeTwo = TerminalMeta(id: TerminalID(), name: "e", repoPath: "/Users/me", createdAt: Date())

        let snapshot = ProjectTree.snapshot(
            favoritePaths: ["/p/api"], repos: [api], workspaces: [],
            terminals: [owned, desktop, tmp, homeOne, homeTwo], home: home
        )

        #expect(snapshot.projects.map(\.path) == ["/p/api"])
        #expect(snapshot.others.map(\.label) == ["/tmp/x", "~", "~/Desktop"])
        #expect(snapshot.others[1].terminals.map(\.id) == [homeOne.id, homeTwo.id], "girdi sırası korunur")
        #expect(!snapshot.others.flatMap(\.terminals).contains { $0.id == owned.id }, "sondaki / normalleşir")
    }

    @Test func looseGroupsHonourExtraOwnedPaths() {
        let tab = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/p/open-tab", createdAt: Date())
        #expect(ProjectTree.looseGroups(terminals: [tab], ownedPaths: ["/p/open-tab"]).isEmpty)
        #expect(ProjectTree.looseGroups(terminals: [tab], ownedPaths: []).count == 1)
    }

    @Test func byRecentActivityPutsNewestFirst() {
        let base = Date(timeIntervalSince1970: 0)
        let older = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/x", createdAt: base)
        let newer = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/x", createdAt: base.addingTimeInterval(5))
        #expect(ProjectTree.byRecentActivity([older, newer]) == [newer.id, older.id])
    }
}
