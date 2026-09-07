import XCTest
@testable import LumiKit

final class PlasticHistoryGraphTests: XCTestCase {
    private func changeset(_ id: Int, branch: String, parent: Int?) -> PlasticChangeset {
        PlasticChangeset(changesetID: id, branch: branch, owner: "o", date: Date(timeIntervalSince1970: Double(id)), comment: "c\(id)", parentID: parent)
    }

    func testMapsIDsParentsAndOrdersNewestFirst() {
        let commits = PlasticHistoryGraph.commits(
            from: [changeset(1, branch: "/main", parent: nil), changeset(3, branch: "/main", parent: 2), changeset(2, branch: "/main", parent: 1)],
            currentBranch: "/main"
        )
        XCTAssertEqual(commits.map(\.hash), ["3", "2", "1"])
        XCTAssertEqual(commits.map(\.parentHashes), [["2"], ["1"], []])
        XCTAssertEqual(commits.first?.shortHash, "cs:3")
    }

    func testOnlyBranchTipsCarryReferencesAndCurrentBranchIsMarked() {
        let commits = PlasticHistoryGraph.commits(
            from: [
                changeset(5, branch: "/main/release", parent: 3),
                changeset(4, branch: "/main", parent: 3),
                changeset(3, branch: "/main", parent: 2),
                changeset(2, branch: "/main/release", parent: 1),
            ],
            currentBranch: "/main"
        )
        XCTAssertEqual(commits[0].references, [GitRef(name: "/main/release", kind: .localBranch, isCurrent: false)])
        XCTAssertEqual(commits[1].references, [GitRef(name: "/main", kind: .localBranch, isCurrent: true)])
        XCTAssertTrue(commits[2].references.isEmpty)
        XCTAssertTrue(commits[3].references.isEmpty, "eski changeset branch ucu değildir")
    }

    func testGraphBuildsForkFromMainIntoChildBranch() {
        let commits = PlasticHistoryGraph.commits(
            from: [
                changeset(4, branch: "/main/release", parent: 2),
                changeset(3, branch: "/main", parent: 2),
                changeset(2, branch: "/main", parent: 1),
            ],
            currentBranch: "/main"
        )
        let rows = CommitGraph.build(commits, headHash: PlasticHistoryGraph.headHash(workspaceChangesetID: 3, in: []))
        XCTAssertEqual(rows.map(\.laneIndex), [0, 1, 0], "release ucu ve main ayrı lane, cs:2'de birleşir")
        XCTAssertEqual(CommitGraph.maxLaneCount(rows), 2)
        XCTAssertEqual(rows.last?.outputLanes.map(\.targetHash), ["1"], "pencere dışı parent'ın lane'i açık kalır")
    }

    func testHeadHashOnlyWhenWorkspaceChangesetIsInWindow() {
        let items = [changeset(9, branch: "/main", parent: 8)]
        XCTAssertEqual(PlasticHistoryGraph.headHash(workspaceChangesetID: 9, in: items), "9")
        XCTAssertNil(PlasticHistoryGraph.headHash(workspaceChangesetID: 7, in: items))
        XCTAssertNil(PlasticHistoryGraph.headHash(workspaceChangesetID: nil, in: items))
    }
}
