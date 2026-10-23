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
        XCTAssertEqual(OrchestratorFlightPath.fade(0), 1, "kalkış evresinden tam parlak devralır")
        XCTAssertEqual(OrchestratorFlightPath.fade(1), 0, "inişte söner, bir şey patlamaz")
    }

    /// Kullanıcı isteği: ışık çıktığı yerde bump ölçekle belirip kısa bir an
    /// bekler, sonra uçar.
    func testLaunchPopsWithOvershootThenHoldsBeforeTravel() {
        XCTAssertEqual(OrchestratorFlightPath.launchScale(0), 0, accuracy: 0.0001)
        let peak = stride(from: 0.0, through: 1.0, by: 0.01).map(OrchestratorFlightPath.launchScale).max() ?? 0
        XCTAssertGreaterThan(peak, 1.1, "taşarak büyür")
        XCTAssertEqual(OrchestratorFlightPath.launchScale(OrchestratorFlightPath.popRatio), 1, accuracy: 0.0001)
        XCTAssertEqual(OrchestratorFlightPath.launchScale(0.9), 1, accuracy: 0.0001, "kalan sürede durgun bekler")

        guard case .launch = OrchestratorFlightPath.stage(elapsed: 0.2, launch: 0.35, travel: 0.9) else {
            return XCTFail("bekleme evresinde ışık yerinden kalkmaz")
        }
        XCTAssertEqual(OrchestratorFlightPath.stage(elapsed: 0.35, launch: 0.35, travel: 0.9), .travel(t: 0))
        guard case let .travel(t) = OrchestratorFlightPath.stage(elapsed: 0.8, launch: 0.35, travel: 0.9) else {
            return XCTFail("bekleme bitince uçar")
        }
        XCTAssertEqual(t, 0.5, accuracy: 0.0001)
    }
}
