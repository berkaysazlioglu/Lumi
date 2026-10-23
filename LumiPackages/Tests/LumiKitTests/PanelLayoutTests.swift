import Foundation
import XCTest
@testable import LumiKit

/// `PanelLayout` — kabuğun yerleşim değeri (K33). Tamamen SAF: mutasyonlar yeni
/// değer döndürür, kaynak değer değişmez.
final class PanelLayoutTests: XCTestCase {
    // MARK: - Default'lar

    func testDefaultsMatchTodaysShell() {
        let layout = PanelLayout.defaults
        XCTAssertEqual(layout.items(in: .left), [.tasks, .projects])
        XCTAssertEqual(layout.items(in: .right), [.projectTools])
        XCTAssertEqual(layout.items(in: .bottom), [])
        XCTAssertEqual(layout.visibleSlots, [.left], "sol açık, sağ kapalı (bugünkü default)")
        XCTAssertEqual(layout.width(for: .left), 280)
        XCTAssertEqual(layout.width(for: .bottom), 280)
        XCTAssertEqual(layout.width(for: .right), 340, "sağ proje paneli daha geniş açılır (K42)")
    }

    // MARK: - Sağ kenarda tek panel (karar 124)

    func testOrchestratorSlotDefaults() {
        let layout = PanelLayout.defaults
        XCTAssertEqual(layout.items(in: .innerRight), [.orchestrator])
        XCTAssertFalse(layout.isVisible(.innerRight), "orchestrator paneli kapalı doğar")
        XCTAssertEqual(layout.width(for: .innerRight), PanelLayout.orchestratorPanelWidth)
        XCTAssertTrue(layout.exclusiveRightPanels, "varsayılan: aynı anda tek sağ panel")
    }

    func testExclusiveRuleClosesTheRightEdgePartner() {
        let right = PanelLayout.defaults.settingVisible(.right, true)
        let orchestrator = right.settingVisible(.innerRight, true)
        XCTAssertTrue(orchestrator.isVisible(.innerRight))
        XCTAssertFalse(orchestrator.isVisible(.right), "orchestrator açılınca sağ panel kapanır")

        let back = orchestrator.togglingVisible(.right)
        XCTAssertTrue(back.isVisible(.right))
        XCTAssertFalse(back.isVisible(.innerRight), "sağ panel açılınca orchestrator kapanır")
        XCTAssertTrue(back.isVisible(.left), "sol yuva kuraldan etkilenmez")
    }

    func testBothRightPanelsStayOpenWhenRuleIsOff() {
        let layout = PanelLayout.defaults
            .settingExclusiveRightPanels(false)
            .settingVisible(.right, true)
            .settingVisible(.innerRight, true)
        XCTAssertTrue(layout.isVisible(.right))
        XCTAssertTrue(layout.isVisible(.innerRight))
    }

    func testEnablingRuleWithBothOpenClosesOrchestrator() {
        let both = PanelLayout.defaults
            .settingExclusiveRightPanels(false)
            .settingVisible(.right, true)
            .settingVisible(.innerRight, true)
        let exclusive = both.settingExclusiveRightPanels(true)
        XCTAssertTrue(exclusive.exclusiveRightPanels)
        XCTAssertTrue(exclusive.isVisible(.right))
        XCTAssertFalse(exclusive.isVisible(.innerRight))
    }

    func testHidingASlotNeverOpensItsPartner() {
        let layout = PanelLayout.defaults.settingVisible(.right, true).settingVisible(.right, false)
        XCTAssertFalse(layout.isVisible(.innerRight))
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

    func testMigratingProjectsAfterTasksPreservesOtherLayoutMetadata() {
        let legacy = PanelLayout(
            slots: [.left: [.projects, .fileTree, .tasks], .right: [.projectTools]],
            visibleSlots: [.right],
            widths: [.left: 310, .right: 420],
            autoRevealSlots: [.left]
        )

        let migrated = legacy.migratingProjectsAfterTasks()

        XCTAssertEqual(migrated.items(in: .left), [.fileTree, .tasks, .projects])
        XCTAssertEqual(migrated.items(in: .right), [.projectTools])
        XCTAssertEqual(migrated.visibleSlots, [.right])
        XCTAssertEqual(migrated.width(for: .left), 310)
        XCTAssertEqual(migrated.width(for: .right), 420)
        XCTAssertEqual(migrated.autoRevealSlots, [.left])
    }

    func testMigratingProjectsAfterTasksLeavesProjectsMovedElsewhereAlone() {
        let layout = PanelLayout.defaults.moving(.projects, to: .right, index: 0)
        XCTAssertEqual(layout.migratingProjectsAfterTasks(), layout)
    }

    // MARK: - Sessions → Tasks (karar 55)

    func testMigratingSessionsToTasksReplacesLegacyItemInPlace() {
        let legacy = PanelLayout(
            slots: [.left: [PanelItemID("sessions"), .projects], .right: [.projectTools]],
            visibleSlots: [.left],
            widths: [.left: 310],
            autoRevealSlots: [.left]
        )

        let migrated = legacy.migratingSessionsToTasks()

        XCTAssertEqual(migrated.items(in: .left), [.tasks, .projects], "aynı sırada devralır")
        XCTAssertEqual(migrated.visibleSlots, [.left])
        XCTAssertEqual(migrated.width(for: .left), 310)
        XCTAssertEqual(migrated.autoRevealSlots, [.left])
    }

    func testMigratingSessionsToTasksKeepsTheSlotTheUserMovedItTo() {
        let legacy = PanelLayout(
            slots: [.left: [.projects], .right: [.projectTools, PanelItemID("sessions")]],
            visibleSlots: [.left],
            widths: [:]
        )
        XCTAssertEqual(
            legacy.migratingSessionsToTasks().items(in: .right),
            [.projectTools, .tasks]
        )
    }

    func testMigratingSessionsToTasksIsANoOpWithoutLegacyItem() {
        XCTAssertEqual(PanelLayout.defaults.migratingSessionsToTasks(), PanelLayout.defaults)
    }

    func testMigratingSessionsToTasksLeavesAnExistingTasksItemAlone() {
        let layout = PanelLayout(
            slots: [.left: [.tasks, PanelItemID("sessions")]],
            visibleSlots: [.left],
            widths: [:]
        )
        XCTAssertEqual(layout.migratingSessionsToTasks(), layout)
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
        let moved = PanelLayout.defaults.moving(.tasks, to: .right, index: 0)
        XCTAssertEqual(moved.items(in: .left), [.projects])
        XCTAssertEqual(moved.items(in: .right), [.tasks, .projectTools])
        XCTAssertEqual(moved.slot(of: .tasks), .right)
    }

    func testMovingWithoutIndexAppendsToEnd() {
        let moved = PanelLayout.defaults.moving(.tasks, to: .right)
        XCTAssertEqual(moved.items(in: .right), [.projectTools, .tasks])
    }

    func testMovingClampsOutOfRangeIndex() {
        let high = PanelLayout.defaults.moving(.tasks, to: .right, index: 99)
        XCTAssertEqual(high.items(in: .right), [.projectTools, .tasks])
        let low = PanelLayout.defaults.moving(.tasks, to: .right, index: -5)
        XCTAssertEqual(low.items(in: .right), [.tasks, .projectTools])
    }

    func testMovingWithinSameSlotReorders() {
        let layout = PanelLayout.defaults.moving(.projectTools, to: .left)
        let moved = layout.moving(.projectTools, to: .left, index: 0)
        XCTAssertEqual(moved.items(in: .left), [.projectTools, .tasks, .projects])
    }

    func testMovingNeverDuplicatesAcrossSlots() {
        let moved = PanelLayout.defaults
            .moving(.tasks, to: .right)
            .moving(.tasks, to: .bottom)
        XCTAssertEqual(moved.items(in: .left), [.projects])
        XCTAssertEqual(moved.items(in: .right), [.projectTools])
        XCTAssertEqual(moved.items(in: .bottom), [.tasks])
    }

    func testMutationsDoNotTouchTheSource() {
        let original = PanelLayout.defaults
        _ = original.moving(.tasks, to: .right)
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
        XCTAssertNil(layout.slot(of: .tasks))
    }
}
