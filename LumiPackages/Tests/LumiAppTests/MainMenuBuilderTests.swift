import AppKit
import XCTest
import LumiUI
@testable import LumiAppCore

/// `MainMenuBuilder` menü ağacı + `ShortcutReference` ile GERÇEK senkron testi
/// (plan 2.7). Menü kısayolların tek kaynağıdır (design/03 §2); Settings →
/// Shortcuts tablosu onun aynasıdır. İki taraf ayrıştığı anda burası kırılır.
@MainActor
final class MainMenuBuilderTests: XCTestCase {
    /// Menü aksiyonlarının hedefi — selector'ların var olması yeterli.
    private final class ActionTarget: NSObject {
        @objc func newTerminal(_ sender: Any?) {}
        @objc func closeTerminal(_ sender: Any?) {}
        @objc func openRepoSelector(_ sender: Any?) {}
        @objc func focusNext(_ sender: Any?) {}
        @objc func focusPrevious(_ sender: Any?) {}
        @objc func focusIndex(_ sender: Any?) {}
        @objc func toggleMaximize(_ sender: Any?) {}
        @objc func toggleLeftSidebar(_ sender: Any?) {}
        @objc func toggleRightSidebar(_ sender: Any?) {}
        @objc func openSettings(_ sender: Any?) {}
        @objc func toggleFocusMode(_ sender: Any?) {}
    }

    /// Kullanıcıya sunulan Shortcuts tablosuna BİLİNÇLİ olarak alınmayan,
    /// platform standardı kısayollar (design/03 §2: "standart Edit menüsü …
    /// Window menüsü"). Menüye yeni bir standart item eklenirse bu liste de
    /// güncellenmeli — sessizce kaçmaz.
    private static let systemStandardCombos: Set<[String]> = [
        ["⌘", "X"], // Cut
        ["⌘", "C"], // Copy
        ["⌘", "V"], // Paste
        ["⌘", "A"], // Select All
        ["⌘", "M"], // Window ▸ Minimize
    ]

    private let target = ActionTarget()

    private func buildMenus() -> MainMenuBuilder.Menus {
        MainMenuBuilder.build(actions: MainMenuBuilder.Actions(
            target: target,
            newTerminal: #selector(ActionTarget.newTerminal(_:)),
            closeTerminal: #selector(ActionTarget.closeTerminal(_:)),
            openRepoSelector: #selector(ActionTarget.openRepoSelector(_:)),
            focusNext: #selector(ActionTarget.focusNext(_:)),
            focusPrevious: #selector(ActionTarget.focusPrevious(_:)),
            focusIndex: #selector(ActionTarget.focusIndex(_:)),
            toggleMaximize: #selector(ActionTarget.toggleMaximize(_:)),
            toggleLeftSidebar: #selector(ActionTarget.toggleLeftSidebar(_:)),
            toggleRightSidebar: #selector(ActionTarget.toggleRightSidebar(_:)),
            openSettings: #selector(ActionTarget.openSettings(_:)),
            toggleFocusMode: #selector(ActionTarget.toggleFocusMode(_:))
        ))
    }

    // MARK: - Menü ağacı

    func testBuildsExpectedTopLevelMenus() {
        let menus = buildMenus()
        let titles = menus.mainMenu.items.compactMap(\.submenu?.title)
        XCTAssertEqual(titles, ["", "Shell", "Edit", "Terminal", "View", "Window"])
    }

    func testWindowMenuIsTheOneInTheTree() {
        let menus = buildMenus()
        let windowSubmenu = menus.mainMenu.items.compactMap(\.submenu).first { $0.title == "Window" }
        XCTAssertTrue(windowSubmenu === menus.windowMenu, "windowsMenu ağaçtaki menü olmalı")
    }

    func testTerminalIndexItemsCarryOneBasedTags() {
        let menus = buildMenus()
        let terminalMenu = menus.mainMenu.items.compactMap(\.submenu).first { $0.title == "Terminal" }
        let indexed = terminalMenu?.items.filter { $0.title.hasPrefix("Terminal ") } ?? []
        XCTAssertEqual(indexed.count, 9)
        XCTAssertEqual(indexed.map(\.tag), Array(1...9))
        XCTAssertEqual(indexed.map(\.keyEquivalent), (1...9).map(String.init))
    }

    func testTargetedItemsPointAtActionTarget() {
        let menus = buildMenus()
        let entries = MenuShortcutExtractor.entries(in: menus.mainMenu)
        XCTAssertFalse(entries.isEmpty)
        // Uygulamaya özgü item'ların hepsi dispatcher'a bağlıdır; standart
        // (Cut/Copy/Paste/Select All/Minimize/Quit) item'lar responder chain'e gider.
        let appSpecific = ["New Terminal", "Close Terminal", "Open Repo…", "Settings…"]
        for title in appSpecific {
            let item = findItem(titled: title, in: menus.mainMenu)
            XCTAssertNotNil(item, "\(title) menüde yok")
            XCTAssertTrue(item?.target === target, "\(title) hedefsiz")
        }
    }

    func testCloseTerminalUsesCommandWSoItDoesNotCloseTheWindow() {
        // design/03 §2: Cmd+W terminali kapatır, pencereyi DEĞİL.
        let item = findItem(titled: "Close Terminal", in: buildMenus().mainMenu)
        XCTAssertEqual(item.map(MenuShortcutExtractor.combo(for:)), ["⌘", "W"])
    }

    // MARK: - ShortcutReference ↔ menü aynası (plan 2.7)

    func testEveryReferenceComboExistsInTheMenu() {
        let menuCombos = Set(MenuShortcutExtractor.entries(in: buildMenus().mainMenu).map(\.combo))
        for reference in ShortcutReference.all {
            for combo in expandedCombos(reference) {
                XCTAssertTrue(
                    menuCombos.contains(combo),
                    "\(reference.action): \(combo.joined()) referansta var, menüde YOK"
                )
            }
        }
    }

    func testEveryMenuComboExistsInTheReference() {
        let referenceCombos = Set(ShortcutReference.all.flatMap { self.expandedCombos($0) })
        for entry in MenuShortcutExtractor.entries(in: buildMenus().mainMenu) {
            if Self.systemStandardCombos.contains(entry.combo) { continue }
            XCTAssertTrue(
                referenceCombos.contains(entry.combo),
                "\(entry.title): \(entry.combo.joined()) menüde var, ShortcutReference'ta YOK"
            )
        }
    }

    /// Standart kısayol listesi de menünün aynası olmalı: Edit/Window menüsüne
    /// yeni bir standart item girerse burada görünür.
    func testSystemStandardCombosMatchTheMenu() {
        let menuCombos = Set(MenuShortcutExtractor.entries(in: buildMenus().mainMenu).map(\.combo))
        let referenceCombos = Set(ShortcutReference.all.flatMap { self.expandedCombos($0) })
        XCTAssertEqual(
            menuCombos.subtracting(referenceCombos),
            Self.systemStandardCombos,
            "Shortcuts tablosuna alınmayan kısayol kümesi değişti"
        )
    }

    func testMenuHasNoDuplicateShortcuts() {
        let combos = MenuShortcutExtractor.entries(in: buildMenus().mainMenu).map(\.combo)
        var seen: Set<[String]> = []
        for combo in combos {
            // ⌘M iki kez görünür gibi durmasın: Maximize ⌘⌃M, Minimize ⌘M.
            XCTAssertTrue(seen.insert(combo).inserted, "çakışan kısayol: \(combo.joined())")
        }
    }

    // MARK: - Yardımcılar

    /// `ShortcutReference` aralıkları iki uç kombo ile ifade eder ("⌘1 – ⌘9");
    /// menüde 9 ayrı item vardır. Karşılaştırma için aralık açılır.
    private func expandedCombos(_ reference: ShortcutReference) -> [[String]] {
        guard reference.combos.count == 2,
              let first = reference.combos.first?.last,
              let last = reference.combos.last?.last,
              let lower = Int(first), let upper = Int(last), lower < upper else {
            return reference.combos
        }
        let modifiers = reference.combos[0].dropLast()
        return (lower...upper).map { Array(modifiers) + [String($0)] }
    }

    private func findItem(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let submenu = item.submenu, let found = findItem(titled: title, in: submenu) {
                return found
            }
        }
        return nil
    }
}
