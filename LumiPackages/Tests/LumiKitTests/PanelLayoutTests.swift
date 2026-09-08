import Foundation
import XCTest
@testable import LumiKit

/// `PanelLayout` — kabuğun yerleşim değeri (K33). Tamamen SAF: mutasyonlar yeni
/// değer döndürür, kaynak değer değişmez.
final class PanelLayoutTests: XCTestCase {
    // MARK: - Default'lar

    func testDefaultsMatchTodaysShell() {
        let layout = PanelLayout.defaults
        XCTAssertEqual(layout.items(in: .left), [.sessions, .projects])
        XCTAssertEqual(layout.items(in: .right), [.projectTools])
        XCTAssertEqual(layout.items(in: .bottom), [])
        XCTAssertEqual(layout.visibleSlots, [.left], "sol açık, sağ kapalı (bugünkü default)")
        XCTAssertEqual(layout.width(for: .left), 280)
        XCTAssertEqual(layout.width(for: .bottom), 280)
        XCTAssertEqual(layout.width(for: .right), 340, "sağ proje paneli daha geniş açılır (K42)")
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

    func testMigratingProjectsAfterSessionsPreservesOtherLayoutMetadata() {
        let legacy = PanelLayout(
            slots: [.left: [.projects, .fileTree, .sessions], .right: [.projectTools]],
            visibleSlots: [.right],
            widths: [.left: 310, .right: 420],
            autoRevealSlots: [.left]
        )

        let migrated = legacy.migratingProjectsAfterSessions()

        XCTAssertEqual(migrated.items(in: .left), [.fileTree, .sessions, .projects])
        XCTAssertEqual(migrated.items(in: .right), [.projectTools])
        XCTAssertEqual(migrated.visibleSlots, [.right])
        XCTAssertEqual(migrated.width(for: .left), 310)
        XCTAssertEqual(migrated.width(for: .right), 420)
        XCTAssertEqual(migrated.autoRevealSlots, [.left])
    }

    func testMigratingProjectsAfterSessionsLeavesProjectsMovedElsewhereAlone() {
        let layout = PanelLayout.defaults.moving(.projects, to: .right, index: 0)
        XCTAssertEqual(layout.migratingProjectsAfterSessions(), layout)
    }

    // MARK: - Auto-reveal (karar 44)

    func testDefaultsHaveNoAutoRevealSlots() {
        XCTAssertTrue(PanelLayout.defaults.autoRevealSlots.isEmpty)
        XCTAssertFalse(PanelLayout.defaults.isAutoReveal(.left))
    }

    func testSettingAutoRevealReturnsNewValueAndKeepsSource() {
        let base = PanelLayout.defaults
        let enabled = base.settingAutoReveal(.right, true)
        XCTAssertTrue(enabled.isAutoReveal(.right))
        XCTAssertFalse(base.isAutoReveal(.right), "kaynak değişmez")
        XCTAssertEqual(enabled.visibleSlots, base.visibleSlots, "görünürlüğe dokunmaz")
        XCTAssertFalse(enabled.settingAutoReveal(.right, false).isAutoReveal(.right))
    }

    func testAutoRevealIsIndependentFromVisibility() {
        let layout = PanelLayout.defaults
            .settingAutoReveal(.left, true)
            .settingVisible(.left, false)
        XCTAssertTrue(layout.isAutoReveal(.left))
        XCTAssertFalse(layout.isVisible(.left))
    }

    // MARK: - Taşıma (ana hedef)

    func testMovingItemLeftToRightRemovesItFromSource() {
        let moved = PanelLayout.defaults.moving(.sessions, to: .right, index: 0)
        XCTAssertEqual(moved.items(in: .left), [.projects])
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
        XCTAssertEqual(moved.items(in: .left), [.projectTools, .sessions, .projects])
    }

    func testMovingNeverDuplicatesAcrossSlots() {
        let moved = PanelLayout.defaults
            .moving(.sessions, to: .right)
            .moving(.sessions, to: .bottom)
        XCTAssertEqual(moved.items(in: .left), [.projects])
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
