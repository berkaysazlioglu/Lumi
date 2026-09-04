import XCTest
@testable import LumiUI

final class TabStripInteractionModelTests: XCTestCase {
    // a: 0–100, b: 104–204, c: 208–308
    private let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 100, height: 32),
        "b": CGRect(x: 104, y: 0, width: 100, height: 32),
        "c": CGRect(x: 208, y: 0, width: 100, height: 32),
    ]

    func testDragRightOntoNeighborTargetsIt() {
        XCTAssertEqual(TabStripInteractionModel.dropTarget(for: "a", translation: 100, frames: frames), "b")
    }

    func testDragLeftOntoNeighborTargetsIt() {
        XCTAssertEqual(TabStripInteractionModel.dropTarget(for: "c", translation: -150, frames: frames), "b")
    }

    func testSmallDragStaysOnSelfReturnsNil() {
        XCTAssertNil(TabStripInteractionModel.dropTarget(for: "b", translation: 10, frames: frames))
    }

    func testOvershootPastLastTargetsLast() {
        XCTAssertEqual(TabStripInteractionModel.dropTarget(for: "a", translation: 500, frames: frames), "c")
    }

    func testOvershootBeforeFirstTargetsFirst() {
        XCTAssertEqual(TabStripInteractionModel.dropTarget(for: "c", translation: -500, frames: frames), "a")
    }

    func testGapBetweenChipsReturnsNil() {
        XCTAssertNil(TabStripInteractionModel.dropTarget(for: "a", translation: 52, frames: frames))
    }

    func testUnknownTabReturnsNil() {
        XCTAssertNil(TabStripInteractionModel.dropTarget(for: "zzz", translation: 100, frames: frames))
    }

    func testCloseButtonRectSitsAtTrailingEdge() {
        let rect = TabStripInteractionModel.closeButtonRect(in: CGRect(x: 100, y: 0, width: 150, height: 34))
        XCTAssertEqual(rect, CGRect(x: 226, y: 8, width: 18, height: 18))
    }
}
