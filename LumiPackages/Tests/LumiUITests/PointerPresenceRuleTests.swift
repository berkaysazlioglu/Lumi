import CoreGraphics
import XCTest
@testable import LumiUI

/// Kenar hover sensörünün **saf** kararları (karar 59, 99). Bu kurallar karar
/// 44'ün üç hover hatasını kapatır (terminal üstünde tetiklenmeme, popover
/// açılınca yanlış kapanma, kaçan çıkışta kapanmama) ve başka yerden açılan
/// popover'ın paneli açmasını engeller.
final class PointerPresenceRuleTests: XCTestCase {
    private let region = CGRect(x: 0, y: 0, width: 100, height: 400)
    private let inRegion = CGPoint(x: 50, y: 200)
    private let outOfRegion = CGPoint(x: 400, y: 200)

    private func isInside(
        pointer: CGPoint,
        region: CGRect?? = .none,
        isAppActive: Bool = true,
        isPointerInOwnedWindow: Bool = false,
        isMenuHeld: Bool = false
    ) -> Bool {
        PointerPresenceRule.isInside(
            pointer: pointer,
            region: region ?? self.region,
            isAppActive: isAppActive,
            isPointerInOwnedWindow: isPointerInOwnedWindow,
            isMenuHeld: isMenuHeld
        )
    }

    // MARK: - isInside

    func testPointerInsideRegionIsInside() {
        XCTAssertTrue(isInside(pointer: inRegion))
    }

    func testPointerOutsideRegionIsOutside() {
        XCTAssertFalse(isInside(pointer: outOfRegion))
    }

    /// Panelin kendi popover'ı bölgenin dışına taşsa bile panel açık kalır.
    func testPointerInOwnedWindowStaysInsideEvenOutsideRegion() {
        XCTAssertTrue(isInside(pointer: outOfRegion, isPointerInOwnedWindow: true))
    }

    /// Panelden başlayan sağ tık menüsü sürerken panel kapanmaz.
    func testMenuHeldStaysInsideEvenOutsideRegion() {
        XCTAssertTrue(isInside(pointer: outOfRegion, isMenuHeld: true))
    }

    func testInactiveAppIsAlwaysOutside() {
        XCTAssertFalse(isInside(pointer: inRegion, isAppActive: false, isPointerInOwnedWindow: true, isMenuHeld: true))
    }

    /// Pencereye girmemiş / gizli view: ölçülebilir bölge yok → hover da yok.
    func testMissingRegionIsOutside() {
        XCTAssertFalse(isInside(pointer: inRegion, region: .some(nil)))
    }

    // MARK: - ownedWindows

    /// İmleç paneldeyken açılan popover panele aittir.
    func testWindowAppearingWhileInsideIsOwned() {
        let owned = PointerPresenceRule.ownedWindows(
            attached: [7], previouslyAttached: [], owned: [], wasInside: true
        )
        XCTAssertEqual(owned, [7])
    }

    /// Asıl hata (karar 99): top bar'dan açılan popover paneli açmamalı.
    func testWindowAppearingWhileOutsideIsNotOwned() {
        let owned = PointerPresenceRule.ownedWindows(
            attached: [7], previouslyAttached: [], owned: [], wasInside: false
        )
        XCTAssertTrue(owned.isEmpty)
    }

    /// Önceden açık olan pencere, imleç sonradan panele girince sahiplenilmez.
    func testPreexistingWindowIsNotAdoptedOnEnter() {
        let owned = PointerPresenceRule.ownedWindows(
            attached: [7], previouslyAttached: [7], owned: [], wasInside: true
        )
        XCTAssertTrue(owned.isEmpty)
    }

    /// Kapanan pencerenin sahipliği kendiliğinden düşer — sayaç yok.
    func testClosedWindowIsReleased() {
        let owned = PointerPresenceRule.ownedWindows(
            attached: [], previouslyAttached: [7], owned: [7], wasInside: true
        )
        XCTAssertTrue(owned.isEmpty)
    }

    /// Sahip olunan popover'ın üstünde açılan alt menü de panele aittir;
    /// imleç panelden çıksa da sahiplik korunur.
    func testNestedSubmenuChainsOwnership() {
        let owned = PointerPresenceRule.ownedWindows(
            attached: [7, 8], previouslyAttached: [7], owned: [7], wasInside: true
        )
        XCTAssertEqual(owned, [7, 8])
        let afterLeaving = PointerPresenceRule.ownedWindows(
            attached: [7, 8], previouslyAttached: [7, 8], owned: owned, wasInside: false
        )
        XCTAssertEqual(afterLeaving, [7, 8])
    }
}
