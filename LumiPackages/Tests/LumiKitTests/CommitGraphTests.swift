import Foundation
import XCTest

@testable import LumiKit

/// Commit graph lane algoritmasının saf testleri (Orca `buildGitHistoryViewModels`
/// portu). Girdi her zaman TOPOLOJİK sırada, çocuk → parent yönünde.
final class CommitGraphTests: XCTestCase {
    // MARK: - Yardımcı

    private func commit(
        _ hash: String,
        parents: [String] = [],
        refs: [GitRef] = []
    ) -> GitCommit {
        GitCommit(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            message: "m-\(hash)",
            author: "a",
            date: Date(timeIntervalSince1970: 0),
            parentHashes: parents,
            references: refs
        )
    }

    // MARK: - Testler

    func testLinearChainStaysInSingleLane() {
        let commits = [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertEqual(rows.map(\.laneIndex), [0, 0, 0])
        XCTAssertEqual(rows.map { $0.outputLanes.count }, [1, 1, 0])
        XCTAssertEqual(CommitGraph.maxLaneCount(rows), 1)
    }

    func testBranchDivergenceOpensSecondLane() {
        // c ve d ayrı tepeler; ikisi de a'ya iner.
        let commits = [
            commit("c", parents: ["a"]),
            commit("d", parents: ["a"]),
            commit("a"),
        ]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertEqual(rows[0].laneIndex, 0)
        // d, input lane'lerde yok → yeni lane açar.
        XCTAssertEqual(rows[1].laneIndex, 1)
        XCTAssertEqual(rows[1].outputLanes.count, 2)
        XCTAssertEqual(CommitGraph.maxLaneCount(rows), 2)
    }

    func testMergeCommitCollapsesTwoInputsIntoOneOutputLanePerParent() {
        let commits = [
            commit("m", parents: ["a", "b"]),
            commit("a", parents: ["r"]),
            commit("b", parents: ["r"]),
            commit("r"),
        ]

        let rows = CommitGraph.build(commits, headHash: "m")

        XCTAssertTrue(rows[0].isMerge)
        XCTAssertEqual(rows[0].inputLanes.count, 0)
        XCTAssertEqual(rows[0].outputLanes.map(\.targetHash), ["a", "b"])
        XCTAssertEqual(rows[0].mergeParentLaneIndex, 1, "ikinci parent'ın lane'i")
        XCTAssertEqual(rows[1].laneIndex, 0)
        XCTAssertEqual(rows[2].laneIndex, 1)
    }

    func testClosedLaneShiftsFollowingLanesLeft() {
        // b, iki tepeden (x, y) sonra tek lane'e iner; kalan lane sola kayar.
        let commits = [
            commit("x", parents: ["t"]),
            commit("y", parents: ["t"]),
            commit("t", parents: ["s"]),
            commit("s"),
        ]

        let rows = CommitGraph.build(commits, headHash: "x")

        XCTAssertEqual(rows[1].outputLanes.map(\.targetHash), ["t", "t"])
        // t satırı: iki input lane'i de t'yi hedefliyor → tek çıkış lane'i kalır.
        XCTAssertEqual(rows[2].laneIndex, 0)
        XCTAssertEqual(rows[2].outputLanes.map(\.targetHash), ["s"])
        XCTAssertEqual(rows[3].laneIndex, 0)
    }

    func testLaneColorStaysStableAlongAChain() {
        let commits = [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a", parents: ["z"]),
        ]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertEqual(Set(rows.map(\.nodeColorIndex)).count, 1, "zincir boyunca renk değişmemeli")
    }

    func testCurrentBranchGetsPaletteIndexZero() {
        let commits = [
            commit("c", parents: ["b"], refs: [GitRef(name: "main", kind: .localBranch, isCurrent: true)]),
            commit("b", parents: ["a"]),
            commit("a"),
        ]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertEqual(rows[0].nodeColorIndex, 0)
        XCTAssertTrue(rows[0].isHead)
        XCTAssertFalse(rows[1].isHead)
    }

    func testSideLanesUseDistinctPaletteIndexes() {
        let commits = [
            commit("c", parents: ["a"], refs: [GitRef(name: "main", kind: .localBranch, isCurrent: true)]),
            commit("d", parents: ["a"]),
            commit("a"),
        ]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertNotEqual(rows[0].nodeColorIndex, rows[1].nodeColorIndex)
        XCTAssertTrue(rows.allSatisfy { $0.nodeColorIndex < CommitGraph.paletteSize })
    }

    func testRootCommitKeepsOtherLanesOpen() {
        // Root (parent'sız) commit yalnız KENDİ lane'ini kapatır; yandaki
        // bağımsız tepenin lane'i düşmez.
        let commits = [
            commit("c", parents: ["a"]),
            commit("d"),
            commit("a"),
        ]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertEqual(rows[1].laneIndex, 1)
        XCTAssertEqual(rows[1].outputLanes.map(\.targetHash), ["a"])
        XCTAssertEqual(rows[2].laneIndex, 0)
    }

    func testEmptyInputProducesNoRows() {
        XCTAssertTrue(CommitGraph.build([], headHash: nil).isEmpty)
        XCTAssertEqual(CommitGraph.maxLaneCount([]), 1, "boş graph'ta da kolon genişliği 1 lane")
    }
}
