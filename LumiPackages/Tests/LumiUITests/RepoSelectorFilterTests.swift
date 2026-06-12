import LumiKit
import LumiState
import XCTest
@testable import LumiUI

/// RepoSelector dropdown filtre mantığı (spec/22 §2.3): açık tab'lar gizlenir,
/// isimde case-insensitive substring, grup yapısı korunur; klavye navigasyonu
/// collapsed grupları atlayan düz liste üzerinde çalışır.
@MainActor
final class RepoSelectorFilterTests: XCTestCase {
    private func repo(_ name: String, path: String? = nil, isGit: Bool = true) -> Repo {
        Repo(name: name, path: path ?? "/ws/\(name)", isGitRepo: isGit, source: .projectsRoot)
    }

    private func makeGroups() -> [RepoStore.RepoGroup] {
        [
            RepoStore.RepoGroup(id: "__projects_root__", label: "Projects Root", repos: [
                repo("Lumi"), repo("ai-orchestrator"), repo("SandOut"),
            ]),
            RepoStore.RepoGroup(id: "extra", label: "Github", repos: [
                repo("lumi-docs"), repo("notes", isGit: false),
            ]),
        ]
    }

    func testOpenTabsAreHidden() {
        let result = RepoSelectorView.filteredGroups(
            makeGroups(),
            openTabPaths: ["/ws/Lumi", "/ws/notes"],
            query: ""
        )

        XCTAssertEqual(result[0].repos.map(\.name), ["ai-orchestrator", "SandOut"])
        XCTAssertEqual(result[1].repos.map(\.name), ["lumi-docs"])
    }

    func testQueryFiltersCaseInsensitiveSubstring() {
        let result = RepoSelectorView.filteredGroups(
            makeGroups(),
            openTabPaths: [],
            query: "LUMI"
        )

        XCTAssertEqual(result[0].repos.map(\.name), ["Lumi"])
        XCTAssertEqual(result[1].repos.map(\.name), ["lumi-docs"])
    }

    func testGroupStructurePreservedEvenWhenEmpty() {
        // Boş kalan grup düşmez — gruplu görünümde "No repositories found" gösterilir
        let result = RepoSelectorView.filteredGroups(
            makeGroups(),
            openTabPaths: [],
            query: "SandOut"
        )

        XCTAssertEqual(result.map(\.id), ["__projects_root__", "extra"])
        XCTAssertTrue(result[1].repos.isEmpty)
    }

    func testWhitespaceOnlyQueryMatchesAll() {
        let result = RepoSelectorView.filteredGroups(
            makeGroups(),
            openTabPaths: [],
            query: "   "
        )

        XCTAssertEqual(result[0].repos.count, 3)
    }

    func testFlatReposSkipsCollapsedGroups() {
        // Klavye navigasyonu yalnız AÇIK grupların repoları üzerinde gezer
        let flat = RepoSelectorView.flatRepos(
            makeGroups(),
            collapsed: ["__projects_root__"]
        )

        XCTAssertEqual(flat.map(\.name), ["lumi-docs", "notes"])
    }

    func testFlatReposPreservesGroupOrder() {
        let flat = RepoSelectorView.flatRepos(makeGroups(), collapsed: [])

        XCTAssertEqual(
            flat.map(\.name),
            ["Lumi", "ai-orchestrator", "SandOut", "lumi-docs", "notes"]
        )
    }
}
