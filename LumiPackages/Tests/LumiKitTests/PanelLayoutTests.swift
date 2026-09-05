import Foundation
import XCTest
@testable import LumiKit

/// `PanelLayout` — kabuğun yerleşim değeri (K33). Tamamen SAF: mutasyonlar yeni
/// değer döndürür, kaynak değer değişmez.
final class PanelLayoutTests: XCTestCase {
    // MARK: - Default'lar

    func testDefaultsMatchTodaysShell() {
        let layout = PanelLayout.defaults
        XCTAssertEqual(layout.items(in: .left), [.sessions])
        XCTAssertEqual(layout.items(in: .right), [.projectTools])
        XCTAssertEqual(layout.items(in: .bottom), [])
        XCTAssertEqual(layout.visibleSlots, [.left], "sol açık, sağ kapalı (bugünkü default)")
        for slot in PanelSlot.allCases {
            XCTAssertEqual(layout.width(for: slot), 280)
        }
    }

    func testMigratingDerivesVisibilityFromLegacyBooleans() {
        XCTAssertEqual(PanelLayout.migrating(leftOpen: true, rightOpen: false).visibleSlots, [.left])
        XCTAssertEqual(PanelLayout.migrating(leftOpen: false, rightOpen: true).visibleSlots, [.right])
        XCTAssertEqual(PanelLayout.migrating(leftOpen: true, rightOpen: true).visibleSlots, [.left, .right])
        XCTAssertTrue(PanelLayout.migrating(leftOpen: false, rightOpen: false).visibleSlots.isEmpty)
        XCTAssertEqual(
            PanelLayout.migrating(leftOpen: false, rightOpen: false).slots,
            PanelLayout.defaults.slots,
            "yerleşim default'tan gelir — yalnız görünürlük migrate edilir"
        )
    }

    // MARK: - Taşıma (ana hedef)

    func testMovingItemLeftToRightRemovesItFromSource() {
        let moved = PanelLayout.defaults.moving(.sessions, to: .right, index: 0)
        XCTAssertEqual(moved.items(in: .left), [])
        XCTAssertEqual(moved.items(in: .right), [.sessions, .projectTools])
        XCTAssertEqual(moved.slot(of: .sessions), .right)
    }

    func testMovingWithoutIndexAppendsToEnd() {
        let moved = PanelLayout.defaults.moving(.sessions, to: .right)
        XCTAssertEqual(moved.items(in: .right), [.projectTools, .sessions])
    }

    func testMovingClampsOutOfRangeIndex() {
        let high = PanelLayout.defaults.moving(.sessions, to: .right, index: 99)
        XCTAssertEqual(high.items(in: .right), [.projectTools, .sessions])
        let low = PanelLayout.defaults.moving(.sessions, to: .right, index: -5)
        XCTAssertEqual(low.items(in: .right), [.sessions, .projectTools])
    }

    func testMovingWithinSameSlotReorders() {
        let layout = PanelLayout.defaults.moving(.projectTools, to: .left)
        let moved = layout.moving(.projectTools, to: .left, index: 0)
        XCTAssertEqual(moved.items(in: .left), [.projectTools, .sessions])
    }

    func testMovingNeverDuplicatesAcrossSlots() {
        let moved = PanelLayout.defaults
            .moving(.sessions, to: .right)
            .moving(.sessions, to: .bottom)
        XCTAssertEqual(moved.items(in: .left), [])
        XCTAssertEqual(moved.items(in: .right), [.projectTools])
        XCTAssertEqual(moved.items(in: .bottom), [.sessions])
    }

    func testMutationsDoNotTouchTheSource() {
        let original = PanelLayout.defaults
        _ = original.moving(.sessions, to: .right)
        _ = original.settingVisible(.right, true)
        _ = original.settingWidth(400, for: .left)
        XCTAssertEqual(original, PanelLayout.defaults, "değer tipi mutasyonla değişmez")
    }

    // MARK: - Görünürlük / genişlik

    func testToggleAndSetVisibility() {
        let toggled = PanelLayout.defaults.togglingVisible(.right)
        XCTAssertTrue(toggled.isVisible(.right))
        XCTAssertFalse(toggled.togglingVisible(.right).isVisible(.right))
        XCTAssertFalse(PanelLayout.defaults.settingVisible(.left, false).isVisible(.left))
    }

    func testWidthIsClampedToBounds() {
        XCTAssertEqual(
            PanelLayout.defaults.settingWidth(10_000, for: .left).width(for: .left),
            PanelLayout.maxWidth
        )
        XCTAssertEqual(
            PanelLayout.defaults.settingWidth(0, for: .left).width(for: .left),
            PanelLayout.minWidth
        )
        XCTAssertEqual(
            PanelLayout.defaults.settingWidth(320, for: .right).width(for: .right),
            320
        )
    }

    func testUnknownSlotFallsBackToDefaultWidth() {
        let layout = PanelLayout(slots: [:], visibleSlots: [], widths: [:])
        XCTAssertEqual(layout.width(for: .left), PanelLayout.defaultWidth)
        XCTAssertEqual(layout.items(in: .left), [])
        XCTAssertNil(layout.slot(of: .sessions))
    }
}
