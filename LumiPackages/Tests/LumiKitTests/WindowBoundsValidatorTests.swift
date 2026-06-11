import Foundation
import XCTest
@testable import LumiKit

final class WindowBoundsValidatorTests: XCTestCase {
    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondScreen = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

    func testBoundsOnMainScreenValid() {
        let bounds = WindowBounds(x: 100, y: 100, width: 1400, height: 900)
        XCTAssertNotNil(WindowBoundsValidator.validated(bounds, screens: [mainScreen]))
    }

    func testBoundsOnDisconnectedScreenInvalid() {
        // İkinci monitörde kaydedilmiş, artık yalnız ana ekran var (spec/30 senaryosu)
        let bounds = WindowBounds(x: 2200, y: 200, width: 1400, height: 900)
        XCTAssertNotNil(
            WindowBoundsValidator.validated(bounds, screens: [mainScreen, secondScreen])
        )
        XCTAssertNil(WindowBoundsValidator.validated(bounds, screens: [mainScreen]))
    }

    func testBarelyOverlappingBoundsInvalid() {
        // Yalnız birkaç piksel görünür → kullanılamaz, default'a düş
        let bounds = WindowBounds(x: 1890, y: 100, width: 1400, height: 900)
        let intersectionWidth = mainScreen.maxX - 1890 // 30px < minimum
        XCTAssertLessThan(intersectionWidth, WindowBoundsValidator.minimumVisibleWidth)
        XCTAssertNil(WindowBoundsValidator.validated(bounds, screens: [mainScreen]))
    }

    func testDegenerateSizeInvalid() {
        XCTAssertNil(WindowBoundsValidator.validated(
            WindowBounds(x: 0, y: 0, width: 50, height: 40), screens: [mainScreen]
        ))
    }
}
