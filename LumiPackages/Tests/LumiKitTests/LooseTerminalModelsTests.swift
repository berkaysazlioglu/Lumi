import LumiKit
import XCTest

/// Karar 108: serbest terminal kuralı, konum adayları ve etiket.
final class LooseTerminalModelsTests: XCTestCase {
    private let home = "/Users/me"

    // MARK: - LooseTerminalRule

    func testPathOutsideProjectsWorkspacesAndTabsIsLoose() {
        XCTAssertTrue(LooseTerminalRule.isLoose(
            path: "/Users/me", projectPaths: ["/r/alpha"], workspacePaths: ["/w/one"], openTabs: ["/r/beta"]
        ))
    }

    func testProjectWorkspaceOrOpenTabPathIsNotLoose() {
        for path in ["/r/alpha", "/w/one", "/r/beta"] {
            XCTAssertFalse(LooseTerminalRule.isLoose(
                path: path, projectPaths: ["/r/alpha"], workspacePaths: ["/w/one"], openTabs: ["/r/beta"]
            ), path)
        }
    }

    func testRuleComparesNormalizedPaths() {
        XCTAssertFalse(LooseTerminalRule.isLoose(
            path: "/r/alpha/", projectPaths: ["/r/x/../alpha"], workspacePaths: [], openTabs: []
        ))
    }

    func testSubdirectoryOfProjectIsStillLoose() {
        XCTAssertTrue(LooseTerminalRule.isLoose(
            path: "/r/alpha/sub", projectPaths: ["/r/alpha"], workspacePaths: [], openTabs: []
        ))
    }

    // MARK: - LooseTerminalPath

    func testTildeExpandsAndTrailingSlashDrops() {
        XCTAssertEqual(LooseTerminalPath.normalized("~", home: home), home)
        XCTAssertEqual(LooseTerminalPath.normalized("~/Desktop/", home: home), "/Users/me/Desktop")
        XCTAssertEqual(LooseTerminalPath.normalized("~other/x", home: home).hasPrefix(home), false)
    }

    func testDisplayLabelAbbreviatesHomeOnly() {
        XCTAssertEqual(LooseTerminalPath.displayLabel(home, home: home), "~")
        XCTAssertEqual(LooseTerminalPath.displayLabel("/Users/me/Desktop", home: home), "~/Desktop")
        XCTAssertEqual(LooseTerminalPath.displayLabel("/Users/meow", home: home), "/Users/meow")
        XCTAssertEqual(LooseTerminalPath.displayLabel("/private/tmp", home: home), "/private/tmp")
    }

    // MARK: - LooseTerminalLocations.candidates

    func testHomeIsAlwaysFirstEvenWithoutSourceRoots() {
        let candidates = LooseTerminalLocations.candidates(
            projectsRoot: "", additionalPaths: [], recent: [], home: home
        )
        XCTAssertEqual(candidates, [LooseTerminalLocation(path: home, kind: .home, label: "~")])
    }

    func testOrderIsHomeThenRootsThenRecentAndRepoEntriesAreSkipped() {
        let candidates = LooseTerminalLocations.candidates(
            projectsRoot: "~/wkspaces",
            additionalPaths: [
                AdditionalPath(id: "a", path: "/src", type: .root),
                AdditionalPath(id: "b", path: "/single/repo", type: .repo),
            ],
            recent: ["/Users/me/Desktop"],
            home: home
        )
        XCTAssertEqual(candidates.map(\.path), ["/Users/me", "/Users/me/wkspaces", "/src", "/Users/me/Desktop"])
        XCTAssertEqual(candidates.map(\.kind), [.home, .sourceRoot, .sourceRoot, .recent])
        XCTAssertEqual(candidates[1].label, "~/wkspaces")
    }

    func testRecentDoesNotRepeatHomeOrRootsAndBlankRootsAreSkipped() {
        let candidates = LooseTerminalLocations.candidates(
            projectsRoot: "  ",
            additionalPaths: [AdditionalPath(id: "a", path: "/src/", type: .root)],
            recent: ["~", "/src", "/elsewhere"],
            home: home
        )
        XCTAssertEqual(candidates.map(\.path), ["/Users/me", "/src", "/elsewhere"])
    }

    func testRecentCandidatesAreCapped() {
        let recent = (1...8).map { "/p\($0)" }
        let candidates = LooseTerminalLocations.candidates(
            projectsRoot: "", additionalPaths: [], recent: recent, home: home
        )
        XCTAssertEqual(candidates.filter { $0.kind == .recent }.count, LooseTerminalLocations.recentLimit)
    }

    // MARK: - LooseTerminalLocations.recording

    func testRecordingMovesPathToFrontWithoutDuplicates() {
        let recorded = LooseTerminalLocations.recording("~/b", into: ["/Users/me/a", "/Users/me/b/", "/c"], home: home)
        XCTAssertEqual(recorded, ["/Users/me/b", "/Users/me/a", "/c"])
    }

    func testRecordingCapsAtLimit() {
        let recorded = LooseTerminalLocations.recording("/new", into: (1...5).map { "/p\($0)" }, home: home)
        XCTAssertEqual(recorded, ["/new", "/p1", "/p2", "/p3", "/p4"])
    }
}
