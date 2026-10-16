@testable import LumiUI
import XCTest

/// Karar 77 eki: dikkat vurgusu hiç sönmeden nefes alır.
final class AttentionPulseTests: XCTestCase {
    func testPulseStartsFullDimsToFloorAndNeverGoesOut() {
        let period = AttentionPulse.period
        XCTAssertEqual(AttentionPulse.opacity(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(AttentionPulse.opacity(at: period / 2), AttentionPulse.floor, accuracy: 1e-9)
        XCTAssertEqual(AttentionPulse.opacity(at: period), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(AttentionPulse.floor, 0, "tamamen sönmez")
        for step in 0...100 {
            let value = AttentionPulse.opacity(at: period * Double(step) / 37)
            XCTAssertGreaterThanOrEqual(value, AttentionPulse.floor - 1e-9)
            XCTAssertLessThanOrEqual(value, 1 + 1e-9)
        }
    }
}
