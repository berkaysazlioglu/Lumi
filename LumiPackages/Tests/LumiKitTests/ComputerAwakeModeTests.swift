import XCTest
@testable import LumiKit

/// Karar 43: "Keep computer awake" modu — normalize ve aktiflik kuralı.
final class ComputerAwakeModeTests: XCTestCase {
    func testUnknownOrMissingRawValueFallsBackToOff() {
        XCTAssertEqual(ComputerAwakeMode.normalized(nil), .off)
        XCTAssertEqual(ComputerAwakeMode.normalized("bogus"), .off)
        XCTAssertEqual(ComputerAwakeMode.normalized("auto"), .auto)
        XCTAssertEqual(ComputerAwakeMode.normalized("on"), .on)
    }

    func testActivityFollowsModeAndWorkingAgents() {
        XCTAssertTrue(ComputerAwakeMode.on.isActive(workingAgentCount: 0))
        XCTAssertFalse(ComputerAwakeMode.auto.isActive(workingAgentCount: 0))
        XCTAssertTrue(ComputerAwakeMode.auto.isActive(workingAgentCount: 2))
        XCTAssertFalse(ComputerAwakeMode.off.isActive(workingAgentCount: 5))
    }

    func testLabelsMatchOrca() {
        XCTAssertEqual(ComputerAwakeMode.on.label, "On")
        XCTAssertEqual(ComputerAwakeMode.auto.label, "Agent")
        XCTAssertEqual(ComputerAwakeMode.off.label, "Off")
        XCTAssertEqual(ComputerAwakeStatus(mode: .auto, isActive: true).text, "Agent · Active")
        XCTAssertEqual(ComputerAwakeStatus(mode: .off, isActive: false).text, "Off · Inactive")
    }
}
