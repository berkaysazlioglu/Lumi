import AppKit
import XCTest
import LumiKit
import LumiUI
@testable import LumiAppCore

/// Menü ↔ komut tablosu ↔ Shortcuts referansı: TEK KAYNAK doğrulaması
/// (refactor 3.5). Eskiden bu dosya iki elle tutulan listenin aynası olduğunu
/// kanıtlıyordu; artık ikisinin de `AppCommands.all`'dan TÜREDİĞİNİ kanıtlıyor.
@MainActor
final class MainMenuBuilderTests: XCTestCase {
    private let dispatcher = MenuActionDispatcher()

    private func buildMenus() -> MainMenuBuilder.Menus {
        MainMenuBuilder.build(dispatcher: dispatcher)
    }

    // MARK: - Menü ağacı

    func testBuildsExpectedTopLevelMenus() {
        let titles = buildMenus().mainMenu.items.compactMap(\.submenu?.title)
        XCTAssertEqual(titles, ["", "Shell", "Edit", "Terminal", "View", "Window"])
    }

    func testWindowMenuIsTheOneInTheTree() {
        let menus = buildMenus()
        let windowSubmenu = menus.mainMenu.items.compactMap(\.submenu).first { $0.title == "Window" }
        XCTAssertTrue(windowSubmenu === menus.windowMenu, "windowsMenu ağaçtaki menü olmalı")
    }

    func testTerminalIndexItemsCarryOneBasedTags() {
        let terminalMenu = buildMenus().mainMenu.items
            .compactMap(\.submenu).first { $0.title == "Terminal" }
        let indexed = terminalMenu?.items.filter { $0.title.hasPrefix("Terminal ") } ?? []
        XCTAssertEqual(indexed.count, 9)
        XCTAssertEqual(indexed.map(\.tag), Array(1...9))
        XCTAssertEqual(indexed.map(\.keyEquivalent), (1...9).map(String.init))
    }

    func testCloseTerminalUsesCommandWSoItDoesNotCloseTheWindow() {
        // design/03 §2: Cmd+W terminali kapatır, pencereyi DEĞİL.
        let item = findItem(titled: "Close Terminal", in: buildMenus().mainMenu)
        XCTAssertEqual(item.map(MenuShortcutExtractor.combo(for:)), ["⌘", "W"])
    }

    func testSeparatorsFollowTheCommandTable() {
        let shellMenu = buildMenus().mainMenu.items
            .compactMap(\.submenu).first { $0.title == "Shell" }
        // New Terminal, Close Terminal, ─────, Open Repo…
        XCTAssertEqual(
            shellMenu?.items.map { $0.isSeparatorItem ? "—" : $0.title },
            ["New Terminal", "Close Terminal", "—", "Open Repo…"]
        )
    }

    // MARK: - Tek kaynak: menü ≡ AppCommands.all

    /// Tablodaki her komut menüde tam olarak beklenen kombo(lar)la görünür.
    func testEveryCommandInTheTableAppearsInTheMenu() {
        let menuCombos = Set(MenuShortcutExtractor.entries(in: buildMenus().mainMenu).map(\.combo))
        for command in AppCommands.all {
            for combo in command.displayCombosExpanded {
                XCTAssertTrue(
                    menuCombos.contains(combo),
                    "\(command.title): \(combo.joined()) tabloda var, menüde YOK"
                )
            }
        }
    }

    /// Menüde tablonun DIŞINDA hiçbir kısayol yoktur — elle eklenen item
    /// tek kaynağı deler, test kırılır.
    func testMenuIntroducesNoShortcutOutsideTheTable() {
        let tableCombos = Set(AppCommands.all.flatMap(\.displayCombosExpanded))
        for entry in MenuShortcutExtractor.entries(in: buildMenus().mainMenu) {
            XCTAssertTrue(
                tableCombos.contains(entry.combo),
                "\(entry.title): \(entry.combo.joined()) menüde var, AppCommands'ta YOK"
            )
        }
    }

    /// Uygulamaya özgü item'lar dispatcher'a, platform standardı item'lar
    /// responder chain'e gider (design/03 §2).
    func testAppSpecificItemsTargetTheDispatcherAndStandardsDoNot() {
        let menus = buildMenus()
        for command in AppCommands.all where command.indexRange == nil {
            guard let item = findItem(titled: command.title, in: menus.mainMenu) else {
                return XCTFail("\(command.title) menüde yok")
            }
            if command.isSystemStandard || command.id == .quit {
                XCTAssertNil(item.target, "\(command.title) responder chain'e gitmeli")
            } else {
                XCTAssertTrue(item.target === dispatcher, "\(command.title) dispatcher'sız")
                XCTAssertEqual(item.representedObject as? String, command.id.rawValue)
            }
        }
    }

    func testMenuHasNoDuplicateShortcuts() {
        let combos = MenuShortcutExtractor.entries(in: buildMenus().mainMenu).map(\.combo)
        var seen: Set<[String]> = []
        for combo in combos {
            // ⌘M iki kez görünür gibi durmasın: Maximize ⌘⌃M, Minimize ⌘M.
            XCTAssertTrue(seen.insert(combo).inserted, "çakışan kısayol: \(combo.joined())")
        }
    }

    // MARK: - Shortcuts referansı da aynı tablodan türer

    func testShortcutReferenceIsDerivedFromTheSameTable() {
        XCTAssertEqual(
            ShortcutReference.all.map(\.action),
            AppCommands.reference.map { $0.referenceTitle ?? $0.title }
        )
        XCTAssertEqual(
            ShortcutReference.all.map(\.combos),
            AppCommands.reference.map(\.displayCombos)
        )
    }

    /// Shortcuts tablosuna BİLİNÇLİ olarak alınmayan platform standardı
    /// kısayollar (design/03 §2). Menüye yeni bir standart item eklenirse
    /// burası kırılır — sessizce kaçmaz.
    func testSystemStandardCombosAreTheOnlyOnesMissingFromTheReference() {
        let menuCombos = Set(MenuShortcutExtractor.entries(in: buildMenus().mainMenu).map(\.combo))
        let referenced = Set(AppCommands.reference.flatMap(\.displayCombosExpanded))
        XCTAssertEqual(
            menuCombos.subtracting(referenced),
            [
                ["⌘", "X"], // Cut
                ["⌘", "C"], // Copy
                ["⌘", "V"], // Paste
                ["⌘", "A"], // Select All
                ["⌘", "M"], // Window ▸ Minimize
            ],
            "Shortcuts tablosuna alınmayan kısayol kümesi değişti"
        )
    }

    // MARK: - Yardımcı

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

private extension AppCommand {
    /// Menüdeki GERÇEK item'ların komboları: indeksli komut aralığın tamamını
    /// üretir (`displayCombos` yalnız iki ucu gösterir).
    var displayCombosExpanded: [[String]] {
        guard let indexRange else { return displayCombos }
        return indexRange.map { AppCommand.symbols(modifiers) + [String($0)] }
    }
}
