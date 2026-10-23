import XCTest
import LumiWire
@testable import LumiMobileKit

/// Decision 131: sticky prompt header + jump-to-bottom count.
final class ChatScrollNavigationTests: XCTestCase {
    private func turn(_ id: String, _ role: ChatRole) -> FoldedTurn {
        FoldedTurn(id: id, message: ChatMessage(id: id, role: role, blocks: [.text(id, presentation: nil)],
                                                timestampMs: nil, turnId: nil),
                   toolActivity: [])
    }

    private var turns: [FoldedTurn] {
        [turn("u1", .user), turn("a1", .assistant), turn("u2", .user), turn("a2", .assistant), turn("a3", .assistant)]
    }

    private func frame(_ minY: CGFloat, _ maxY: CGFloat) -> ChatTurnFrame {
        ChatTurnFrame(minY: minY, maxY: maxY)
    }

    func testAnswerAtTheTopShowsThePromptBeforeIt() {
        let frames = ["a2": frame(-300, 200), "a3": frame(210, 600)]
        XCTAssertEqual(chatStickyPromptId(turns: turns, frames: frames), "u2")
    }

    func testPromptCutByTheTopEdgeIsItself() {
        let frames = ["u2": frame(-20, 30), "a2": frame(40, 500)]
        XCTAssertEqual(chatStickyPromptId(turns: turns, frames: frames), "u2")
    }

    func testFullyVisiblePromptAtTheTopShowsTheEarlierOne() {
        let frames = ["a1": frame(-200, -10), "u2": frame(0, 40), "a2": frame(50, 500)]
        XCTAssertEqual(chatStickyPromptId(turns: turns, frames: frames), "u1")
    }

    func testNoPromptAboveShowsNothing() {
        let frames = ["u1": frame(0, 40), "a1": frame(50, 500)]
        XCTAssertNil(chatStickyPromptId(turns: turns, frames: frames))
        XCTAssertNil(chatStickyPromptId(turns: turns, frames: [:]))
    }

    func testFarTurnsNeedNoFrame() {
        // u2 is not realized (lazy list) — found by index.
        let frames = ["a3": frame(-100, 700)]
        XCTAssertEqual(chatStickyPromptId(turns: turns, frames: frames), "u2")
    }

    func testPromptUnderTheHeaderCountsAsAbove() {
        // Jumped to u2 (top-anchored): the header keeps naming it, not u1.
        let frames = ["u2": frame(0, 40), "a2": frame(50, 500)]
        XCTAssertEqual(chatStickyPromptId(turns: turns, frames: frames, topInset: 30), "u2")
        XCTAssertEqual(chatStickyPromptId(turns: turns, frames: frames), "u1")
    }

    func testNewTurnCount() {
        XCTAssertEqual(chatNewTurnCount(current: 10, countWhenLeft: nil), 0)
        XCTAssertEqual(chatNewTurnCount(current: 13, countWhenLeft: 10), 3)
        XCTAssertEqual(chatNewTurnCount(current: 8, countWhenLeft: 10), 0, "a /clear shrinks the list")
    }
}
