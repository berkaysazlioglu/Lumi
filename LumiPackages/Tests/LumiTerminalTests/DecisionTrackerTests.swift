import XCTest
@testable import LumiTerminal

final class DecisionTrackerTests: XCTestCase {
    func testStartsNotAwaiting() {
        XCTAssertFalse(DecisionTracker().isAwaitingDecision)
    }

    func testPermissionRequestSetsAwaiting() {
        let tracker = DecisionTracker()
        tracker.onPermissionRequest()
        XCTAssertTrue(tracker.isAwaitingDecision)
    }

    func testWorkingClearsAwaiting() {
        let tracker = DecisionTracker()
        tracker.onPermissionRequest()
        tracker.onWorking()
        XCTAssertFalse(tracker.isAwaitingDecision)
    }

    /// onChange yalnız gerçek değişimde tetiklenir (no-op'lar yayılmaz).
    func testOnChangeFiresOnlyOnRealChange() {
        let tracker = DecisionTracker()
        var changes: [Bool] = []
        tracker.onChange = { changes.append($0) }

        tracker.onWorking()            // zaten false → no-op
        tracker.onPermissionRequest()  // false→true
        tracker.onPermissionRequest()  // true→true no-op
        tracker.onWorking()            // true→false

        XCTAssertEqual(changes, [true, false])
    }

    func testResetClearsAwaiting() {
        let tracker = DecisionTracker()
        tracker.onPermissionRequest()
        tracker.reset()
        XCTAssertFalse(tracker.isAwaitingDecision)
    }
}
