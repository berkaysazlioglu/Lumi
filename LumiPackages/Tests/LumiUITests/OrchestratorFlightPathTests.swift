import CoreGraphics
import XCTest
@testable import LumiUI

/// Karar 126: ışık süzmesinin yolu — uçlardan geçer, yukarı kavis yapar,
/// yumuşak kalkıp iner.
final class OrchestratorFlightPathTests: XCTestCase {
    func testPathRunsBetweenTheEndpointsAndBowsUpward() {
        let path = OrchestratorFlightPath(from: CGPoint(x: 800, y: 300), to: CGPoint(x: 100, y: 400), maxBow: 500)
        XCTAssertEqual(path.point(at: 0), CGPoint(x: 800, y: 300))
        XCTAssertEqual(path.point(at: 1), CGPoint(x: 100, y: 400))
        XCTAssertLessThan(path.point(at: 0.5).y, 350, "orta nokta düz çizginin üstünde")
    }

    func testDirectionDoesNotFlipTheBow() {
        let a = CGPoint(x: 100, y: 400), b = CGPoint(x: 800, y: 300)
        let there = OrchestratorFlightPath(from: a, to: b, maxBow: 500)
        let back = OrchestratorFlightPath(from: b, to: a, maxBow: 500)
        XCTAssertEqual(there.control.x, back.control.x, accuracy: 0.001)
        XCTAssertEqual(there.control.y, back.control.y, accuracy: 0.001)
    }

    func testBowIsCappedAndVariationSpreadsSiblings() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 2000, y: 0)
        let capped = OrchestratorFlightPath(from: a, to: b, variation: 0.5, maxBow: 100)
        XCTAssertEqual(capped.control.y, -100, accuracy: 0.001)
        let low = OrchestratorFlightPath(from: a, to: b, variation: 0, maxBow: 100)
        let high = OrchestratorFlightPath(from: a, to: b, variation: 1, maxBow: 100)
        XCTAssertGreaterThan(low.control.y, high.control.y)
    }

    func testDegenerateFlightStaysPut() {
        let point = CGPoint(x: 5, y: 5)
        XCTAssertEqual(OrchestratorFlightPath(from: point, to: point, maxBow: 100).point(at: 0.5), point)
    }

    func testEasingAndFadeLandSoftly() {
        XCTAssertEqual(OrchestratorFlightPath.eased(0), 0)
        XCTAssertEqual(OrchestratorFlightPath.eased(1), 1)
        XCTAssertEqual(OrchestratorFlightPath.eased(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(OrchestratorFlightPath.fade(0), 0)
        XCTAssertEqual(OrchestratorFlightPath.fade(1), 0, "inişte söner, bir şey patlamaz")
        XCTAssertEqual(OrchestratorFlightPath.fade(0.5), 1)
    }
}
