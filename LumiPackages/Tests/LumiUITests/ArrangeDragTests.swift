import Foundation
import XCTest
@testable import LumiUI

/// Karar 97 Edit modu: bırakma hedefi grid frame'lerinden çözülür.
final class ArrangeDragTests: XCTestCase {
    private let frames = [
        CGRect(x: 0, y: 0, width: 100, height: 100),
        CGRect(x: 110, y: 0, width: 100, height: 100),
        CGRect(x: 0, y: 110, width: 100, height: 100),
    ]

    func testTargetIsTheCardUnderThePointer() {
        XCTAssertEqual(ArrangeDrag.targetIndex(at: CGPoint(x: 150, y: 50), frames: frames), 1)
        XCTAssertEqual(ArrangeDrag.targetIndex(at: CGPoint(x: 20, y: 180), frames: frames), 2)
    }

    /// Kartlar arası boşluğa ya da grid dışına bırakmak takas yapmaz.
    func testGapOrOutsideHasNoTarget() {
        XCTAssertNil(ArrangeDrag.targetIndex(at: CGPoint(x: 105, y: 50), frames: frames))
        XCTAssertNil(ArrangeDrag.targetIndex(at: CGPoint(x: 500, y: 500), frames: frames))
    }
}
