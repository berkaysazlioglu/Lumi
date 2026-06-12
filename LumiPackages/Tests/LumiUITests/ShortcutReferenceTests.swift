import XCTest
@testable import LumiUI

/// Shortcuts sekmesi salt-okunur referansının bütünlüğü (spec/22 §5.6).
/// Liste MainMenuBuilder'ın görsel aynası — sapmaları erken yakalar.
final class ShortcutReferenceTests: XCTestCase {
    func testCoversEveryMenuShortcutAction() {
        let actions = Set(ShortcutReference.all.map(\.action))

        // MainMenuBuilder'daki kullanıcıya görünür kısayol aksiyonları
        let expected: Set<String> = [
            "New Terminal", "Close Terminal", "Open Repository", "Switch to Tab N",
            "Previous Terminal", "Next Terminal", "Maximize Terminal",
            "Toggle Left Sidebar", "Toggle Right Sidebar", "Focus Mode",
            "Settings", "Quit",
        ]

        XCTAssertEqual(actions, expected)
    }

    func testEveryComboIsNonEmpty() {
        for ref in ShortcutReference.all {
            XCTAssertFalse(ref.combos.isEmpty, "\(ref.action) kombosuz")
            for combo in ref.combos {
                XCTAssertFalse(combo.isEmpty, "\(ref.action) boş kombo içeriyor")
                XCTAssertTrue(combo.contains("⌘"), "\(ref.action) ⌘ taşımıyor")
            }
        }
    }

    func testRangeShortcutHasTwoCombos() {
        let tabN = ShortcutReference.all.first { $0.action == "Switch to Tab N" }
        XCTAssertEqual(tabN?.combos.count, 2, "aralıklı kısayol iki kombo (⌘1 – ⌘9) olmalı")
    }

    func testActionsAreUnique() {
        let actions = ShortcutReference.all.map(\.action)
        XCTAssertEqual(actions.count, Set(actions).count, "aksiyon adları benzersiz olmalı")
    }
}
