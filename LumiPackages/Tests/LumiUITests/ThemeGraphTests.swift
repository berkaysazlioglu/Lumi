import LumiKit
import XCTest

@testable import LumiUI

/// Commit graph token'ları: paletin modeldeki basamak sayısıyla eşleşmesi ve
/// kolon genişliğinin lane sayısıyla büyümesi (karar 40).
final class ThemeGraphTests: XCTestCase {
    func testPaletteSizeMatchesGraphModel() {
        XCTAssertEqual(Theme.Graph.laneColors.count, CommitGraph.paletteSize)
        XCTAssertTrue(Theme.Graph.paletteMatchesModel)
    }

    func testLaneColorWrapsInsteadOfCrashingOnOutOfRangeIndex() {
        XCTAssertEqual(Theme.Graph.laneColor(CommitGraph.paletteSize), Theme.Graph.laneColors[0])
        XCTAssertEqual(Theme.Graph.laneColor(-1), Theme.Graph.laneColors.last)
    }

    func testColumnWidthLeavesOneLaneOfPaddingAndNeverCollapses() {
        XCTAssertEqual(Theme.Graph.columnWidth(laneCount: 1), Theme.Graph.laneWidth * 2)
        XCTAssertEqual(Theme.Graph.columnWidth(laneCount: 3), Theme.Graph.laneWidth * 4)
        XCTAssertEqual(
            Theme.Graph.columnWidth(laneCount: 0), Theme.Graph.laneWidth * 2,
            "boş graph'ta bile kolon çökmez (metin hizası korunur)"
        )
    }

    func testCommitRowHeightIsTallEnoughForTwoTextLines() {
        let twoLines = Theme.Typography.Size.body.points + Theme.Typography.Size.caption.points
        XCTAssertGreaterThan(Theme.Row.commit, twoLines)
    }
}
