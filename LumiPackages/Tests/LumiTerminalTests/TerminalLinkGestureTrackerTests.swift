import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// Karar 57: bekleyen link jestinin iptal kuralları.
final class TerminalLinkGestureTrackerTests: XCTestCase {
    private func tracker(hadSelection: Bool = false) -> TerminalLinkGestureTracker {
        var tracker = TerminalLinkGestureTracker()
        tracker.begin(
            link: TerminalClickedLink(text: "/tmp/a.swift"),
            gesture: .actions,
            origin: CGPoint(x: 100, y: 100),
            hadSelection: hadSelection
        )
        return tracker
    }

    func testClickWithoutDragResolves() {
        var tracker = self.tracker()
        let resolved = tracker.finish(hasSelection: false)
        XCTAssertEqual(resolved?.link?.text, "/tmp/a.swift")
        XCTAssertEqual(resolved?.gesture, .actions)
    }

    /// Eşik altı titreme hâlâ tıktır (trackpad'de parmak hiç sabit durmaz).
    func testJitterBelowThresholdStillResolves() {
        var tracker = self.tracker()
        tracker.noteDrag(to: CGPoint(x: 102, y: 101))
        XCTAssertNotNil(tracker.finish(hasSelection: false))
    }

    func testDragCancelsGesture() {
        var tracker = self.tracker()
        tracker.noteDrag(to: CGPoint(x: 140, y: 100))
        XCTAssertNil(tracker.finish(hasSelection: false))
    }

    /// Tıkta zaten seçim varsa tık o seçimi temizlemek içindir.
    func testExistingSelectionCancelsGesture() {
        var tracker = self.tracker(hadSelection: true)
        XCTAssertNil(tracker.finish(hasSelection: false))
    }

    /// Tık sırasında seçim oluştuysa (SwiftTerm kelime seçimi) link açılmaz.
    func testSelectionCreatedDuringClickCancelsGesture() {
        var tracker = self.tracker()
        XCTAssertNil(tracker.finish(hasSelection: true))
    }

    func testFinishClearsPendingGesture() {
        var tracker = self.tracker()
        _ = tracker.finish(hasSelection: false)
        XCTAssertNil(tracker.activeGesture)
        XCTAssertNil(tracker.finish(hasSelection: false))
    }

    func testCancelDropsGesture() {
        var tracker = self.tracker()
        tracker.cancel()
        XCTAssertNil(tracker.activeGesture)
    }
}
