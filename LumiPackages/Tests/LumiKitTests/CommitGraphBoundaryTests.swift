import Foundation
import XCTest

@testable import LumiKit

/// Upstream rengi + sentetik Incoming/Outgoing satırları (Orca
/// `addIncomingOutgoingChangesHistoryItems` portu, karar 98).
final class CommitGraphBoundaryTests: XCTestCase {
    private let main = GitRef(name: "main", kind: .localBranch, isCurrent: true)
    private let originMain = GitRef(name: "origin/main", kind: .remoteBranch)

    private func commit(_ hash: String, parents: [String] = [], refs: [GitRef] = []) -> GitCommit {
        GitCommit(
            hash: hash, shortHash: hash, message: "m-\(hash)", author: "a",
            date: Date(timeIntervalSince1970: 0), parentHashes: parents, references: refs
        )
    }

    private func context(head: String, upstream: String?, mergeBase: String?) -> GitHistoryContext {
        GitHistoryContext(
            currentBranch: "main",
            headHash: head,
            upstream: upstream.map { GitHistoryContext.Upstream(name: "origin/main", hash: $0) },
            mergeBase: mergeBase
        )
    }

    // MARK: - Etiket renkleri

    func testUpstreamCommitGetsRemoteRefColorOnItsLane() {
        let rows = CommitGraph.build(
            [commit("c", parents: ["b"], refs: [main]), commit("b", parents: ["a"], refs: [originMain]), commit("a")],
            headHash: "c",
            upstream: "origin/main"
        )

        XCTAssertEqual(rows[0].nodeColorIndex, CommitGraph.currentBranchColor)
        XCTAssertEqual(rows[1].nodeColorIndex, CommitGraph.remoteRefColor)
    }

    func testWithoutUpstreamBehaviourIsUnchanged() {
        let commits = [commit("c", parents: ["b"], refs: [main]), commit("b", parents: ["a"], refs: [originMain]), commit("a")]

        let rows = CommitGraph.build(commits, headHash: "c")

        XCTAssertEqual(rows.map(\.nodeColorIndex), [0, 0, 0], "Plastic yolu: upstream yoksa renk zinciri aynı kalır")
    }

    func testRefColorIndexColorsOnlyCurrentAndUpstream() {
        XCTAssertEqual(CommitGraph.refColorIndex(main, upstream: "origin/main"), CommitGraph.currentBranchColor)
        XCTAssertEqual(CommitGraph.refColorIndex(originMain, upstream: "origin/main"), CommitGraph.remoteRefColor)
        XCTAssertNil(CommitGraph.refColorIndex(GitRef(name: "v1.0", kind: .tag), upstream: "origin/main"))
        XCTAssertNil(CommitGraph.refColorIndex(originMain, upstream: nil))
    }

    // MARK: - Sınır satırları

    func testNoBoundaryRowsWhenUpToDate() {
        let rows = CommitGraph.build([commit("b", parents: ["a"], refs: [main, originMain]), commit("a")], headHash: "b")

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "b", upstream: "b", mergeBase: nil))

        XCTAssertEqual(result, rows)
    }

    func testOutgoingRowSitsAboveHeadWhenAhead() {
        let rows = CommitGraph.build(
            [commit("c", parents: ["b"], refs: [main]), commit("b", parents: ["a"], refs: [originMain]), commit("a")],
            headHash: "c",
            upstream: "origin/main"
        )

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "c", upstream: "b", mergeBase: "b"))

        XCTAssertEqual(result.map(\.kind), [.outgoingChanges, .commit, .commit, .commit])
        XCTAssertEqual(result[0].commit.parentHashes, ["c"])
        XCTAssertEqual(result[0].commit.author, "main")
        XCTAssertEqual(result[0].outputLanes, result[1].inputLanes, "sınır satırı HEAD'e kesintisiz bağlanır")
        XCTAssertEqual(result[1].laneIndex, 0)
    }

    func testIncomingRowSitsAboveMergeBaseWhenBehind() {
        let rows = CommitGraph.build([commit("b", parents: ["a"], refs: [main]), commit("a")], headHash: "b", upstream: "origin/main")

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "b", upstream: "z", mergeBase: "b"))

        // HEAD == merge-base: yalnız gelen değişiklik var, giden yok.
        XCTAssertEqual(result.map(\.kind), [.incomingChanges, .commit, .commit])
        let incoming = result[0]
        XCTAssertEqual(incoming.commit.hash, CommitGraph.incomingChangesID)
        XCTAssertEqual(incoming.commit.author, "origin/main")
        XCTAssertEqual(incoming.nodeColorIndex, CommitGraph.remoteRefColor)
        XCTAssertEqual(incoming.outputLanes, result[1].inputLanes)
        XCTAssertTrue(
            result[1].inputLanes.contains(CommitGraphLane(targetHash: "b", colorIndex: CommitGraph.remoteRefColor)),
            "upstream lane'i merge-base düğümüne iner"
        )
    }

    func testDivergedBranchGetsBothRows() {
        let rows = CommitGraph.build(
            [commit("c", parents: ["b"], refs: [main]), commit("b", parents: ["a"]), commit("a")],
            headHash: "c",
            upstream: "origin/main"
        )

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "c", upstream: "z", mergeBase: "b"))

        XCTAssertEqual(result.map(\.commit.hash), [CommitGraph.outgoingChangesID, "c", CommitGraph.incomingChangesID, "b", "a"])
        for (upper, lower) in zip(result, result.dropFirst()) {
            XCTAssertEqual(upper.outputLanes, lower.inputLanes, "\(upper.id) → \(lower.id) lane sürekliliği")
        }
    }

    /// Incoming lane'i üstteki satırın lane'lerini kaydırmaz: yan dalın düğümü
    /// kendi rengini ve ilk-parent lane'ini korur.
    func testIncomingLaneDoesNotRecolorTheRowAboveIt() {
        let rows = CommitGraph.build(
            [
                commit("m", parents: ["b", "c"], refs: [main]),
                commit("b", parents: ["d"]),
                commit("c", parents: ["d"]),
                commit("d"),
            ],
            headHash: "m",
            upstream: "origin/main"
        )
        let sideColor = rows[2].nodeColorIndex

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "m", upstream: "z", mergeBase: "d"))

        let side = result.first { $0.id == "c" }
        XCTAssertEqual(side?.nodeColorIndex, sideColor)
        XCTAssertEqual(side?.outputLanes.dropLast(), rows[2].outputLanes[...], "yalnız en sağa incoming lane'i eklenir")
    }

    func testIncomingRowIsSkippedWhenUpstreamIsAlreadyMerged() {
        let rows = CommitGraph.build(
            [commit("m", parents: ["x", "b"], refs: [main]), commit("b", parents: ["r"]), commit("x", parents: ["r"]), commit("r")],
            headHash: "m"
        )

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "m", upstream: "z", mergeBase: "b"))

        XCTAssertFalse(result.contains { $0.kind == .incomingChanges })
    }

    func testIncomingRowIsSkippedWhenMergeBaseIsOutsideTheWindow() {
        let rows = CommitGraph.build([commit("c", parents: ["b"], refs: [main])], headHash: "c")

        let result = CommitGraph.addBoundaryRows(rows, context: context(head: "c", upstream: "z", mergeBase: "old"))

        XCTAssertEqual(result.map(\.kind), [.outgoingChanges, .commit])
    }
}
