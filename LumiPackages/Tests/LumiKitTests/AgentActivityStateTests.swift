import XCTest
@testable import LumiKit

final class AgentActivityStateTests: XCTestCase {
    func testWorkingMapsToRunningAndWaitingVariantsMapToDone() {
        XCTAssertEqual(AgentActivityState(status: .working, isAwaitingDecision: false), .running)
        for status in [TerminalStatus.waitingUnseen, .waitingFocused, .waitingSeen] {
            XCTAssertEqual(AgentActivityState(status: status, isAwaitingDecision: false), .done, "\(status)")
        }
        XCTAssertEqual(AgentActivityState(status: .error, isAwaitingDecision: false), .failed)
        XCTAssertEqual(AgentActivityState(status: .idle, isAwaitingDecision: false), .idle)
    }

    func testAwaitingDecisionWinsOverStatus() {
        XCTAssertEqual(AgentActivityState(status: .working, isAwaitingDecision: true), .awaitingDecision)
        XCTAssertEqual(AgentActivityState(status: .idle, isAwaitingDecision: true), .awaitingDecision)
    }

    func testSortRankPutsAttentionFirstAndIdleLast() {
        let ordered: [AgentActivityState] = [.awaitingDecision, .failed, .running, .done, .idle]
        XCTAssertEqual(ordered.map(\.sortRank), [0, 1, 2, 3, 4])
    }
}
