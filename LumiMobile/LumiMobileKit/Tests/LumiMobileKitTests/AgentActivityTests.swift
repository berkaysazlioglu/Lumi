import XCTest
@testable import LumiMobileKit

final class AgentActivityTests: XCTestCase {
    func testMappingMatchesMacAgentActivityState() {
        XCTAssertEqual(AgentActivity(status: "working", awaitingDecision: false), .running)
        XCTAssertEqual(AgentActivity(status: "working", awaitingDecision: true), .awaitingDecision)
        XCTAssertEqual(AgentActivity(status: "waiting-unseen", awaitingDecision: false), .done)
        XCTAssertEqual(AgentActivity(status: "waiting-seen", awaitingDecision: false), .done)
        XCTAssertEqual(AgentActivity(status: "error", awaitingDecision: false), .failed)
        XCTAssertEqual(AgentActivity(status: "idle", awaitingDecision: false), .idle)
        XCTAssertEqual(AgentActivity(status: "future-thing", awaitingDecision: false), .idle)
    }

    func testTitles() {
        XCTAssertEqual(AgentActivity.running.title, "Running")
        XCTAssertEqual(AgentActivity.awaitingDecision.title, "Needs input")
        XCTAssertEqual(AgentActivity.done.title, "Done")
    }
}
