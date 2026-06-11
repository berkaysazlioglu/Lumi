import XCTest
@testable import LumiTerminal

final class FlowControllerTests: XCTestCase {
    private func makeController() -> FlowController {
        FlowController(highWatermark: 100, lowWatermark: 20)
    }

    func testProceedBelowHighWatermark() {
        let flow = makeController()
        XCTAssertEqual(flow.noteProduced(50), .proceed)
        XCTAssertEqual(flow.inFlight, 50)
    }

    func testSuspendAtHighWatermark() {
        let flow = makeController()
        XCTAssertEqual(flow.noteProduced(50), .proceed)
        XCTAssertEqual(flow.noteProduced(50), .suspend)
    }

    func testHysteresisStaysSuspendedUntilLow() {
        let flow = makeController()
        _ = flow.noteProduced(100)
        XCTAssertFalse(flow.noteConsumed(50)) // 50 > 20 — hâlâ suspend
        XCTAssertTrue(flow.noteConsumed(30))  // 20 <= 20 — resume sinyali bir kez
        XCTAssertFalse(flow.noteConsumed(10)) // artık suspend değil — tekrar sinyal yok
    }

    func testProducedWhileSuspendedKeepsSuspendDirective() {
        let flow = makeController()
        _ = flow.noteProduced(100)
        XCTAssertEqual(flow.noteProduced(1), .suspend)
    }

    func testInFlightNeverGoesNegative() {
        let flow = makeController()
        _ = flow.noteProduced(10)
        flow.noteConsumed(1000)
        XCTAssertEqual(flow.inFlight, 0)
    }

    func testResumeOnlyAfterCrossingLow() {
        let flow = makeController()
        _ = flow.noteProduced(100)
        XCTAssertFalse(flow.noteConsumed(79)) // 21 > 20
        XCTAssertTrue(flow.noteConsumed(1))   // tam 20 → resume
    }
}
