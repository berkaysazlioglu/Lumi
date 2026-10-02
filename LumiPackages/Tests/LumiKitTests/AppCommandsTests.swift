import XCTest
@testable import LumiKit

/// Komut tablosunun bütünlüğü (refactor 3.5). Menü, dispatcher ve Shortcuts
/// tablosu bu tablodan türediği için buradaki kurallar üçünü birden korur.
final class AppCommandsTests: XCTestCase {
    func testCommandIDsAreUnique() {
        let ids = AppCommands.all().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "komut kimlikleri benzersiz olmalı")
    }

    /// Her komutun ya bir tuşu ya da bir indeks aralığı vardır — kısayolsuz
    /// komut menüde sessizce kaybolurdu.
    func testEveryCommandCarriesAShortcut() {
        // Karar 102: About platform geleneği gereği kısayolsuzdur — istisna açık.
        let shortcutless: Set<CommandID> = [.openAbout]
        for command in AppCommands.all() where !shortcutless.contains(command.id) {
            XCTAssertTrue(
                command.key != nil || command.indexRange != nil,
                "\(command.title) kısayolsuz"
            )
            XCTAssertFalse(command.displayCombos.isEmpty, "\(command.title) kombosuz")
        }
    }

    /// Tüm kısayollar ⌘ taşır — TEK istisna indeksli ailelerden ⌃'ye düşenidir
    /// (karar 59/58): varsayılanda proje geçişi, takas edilince terminal
    /// odağı. İstisna burada AÇIKÇA listelenir ki üçüncü bir ⌘'siz kısayol
    /// sessizce eklenemesin.
    func testEveryShortcutUsesCommandModifier() {
        let controlOnly: Set<CommandID> = [.switchToProjectAtIndex]
        for command in AppCommands.all() {
            if controlOnly.contains(command.id) {
                XCTAssertEqual(command.modifiers, [.control], "\(command.title) yalnız ⌃ taşımalı")
                continue
            }
            XCTAssertTrue(
                command.modifiers.contains(.command),
                "\(command.title) ⌘ taşımıyor"
            )
        }
    }

    /// Aynı kombonun iki komuta düşmesi menüde sessiz çakışma yapardı.
    func testNoDuplicateCombosAcrossCommands() {
        var seen: Set<[String]> = []
        for command in AppCommands.all() {
            let combos: [[String]]
            if let range = command.indexRange {
                combos = range.map { AppCommand.symbols(command.modifiers) + [String($0)] }
            } else {
                combos = command.displayCombos
            }
            for combo in combos {
                XCTAssertTrue(seen.insert(combo).inserted, "çakışan kombo: \(combo.joined())")
            }
        }
    }

    // MARK: - Shortcuts referansı

    /// Platform standardı komutlar (Cut/Copy/Paste/Select All/Minimize)
    /// kullanıcı tablosunda GÖRÜNMEZ (design/03 §2).
    func testReferenceExcludesSystemStandardCommands() {
        let referenced = Set(AppCommands.reference().map(\.id))
        for command in AppCommands.all() where command.isSystemStandard {
            XCTAssertFalse(referenced.contains(command.id), "\(command.title) tabloda olmamalı")
        }
        XCTAssertEqual(AppCommands.reference().count, 18, "18 kullanıcı kısayolu")
    }

    func testReferenceIsSortedByReferenceOrder() {
        let orders = AppCommands.reference().map { $0.referenceOrder ?? .max }
        XCTAssertEqual(orders, orders.sorted())
        XCTAssertEqual(Set(orders).count, orders.count, "sıra numaraları benzersiz")
    }

    /// Referans tablosunun gösterdiği etiketler — Settings ekranının paritesi.
    func testReferenceTitlesMatchTheUserFacingList() {
        XCTAssertEqual(
            AppCommands.reference().map { $0.referenceTitle ?? $0.title },
            [
                "New Terminal", "Close Terminal", "Close Project", "Go to Project", "Switch to Project N",
                "Focus Terminal N", "Previous Terminal", "Next Terminal",
                "Maximize Terminal", "Toggle Left Sidebar", "Toggle Right Sidebar",
                "Focus Mode", "Zoom In", "Zoom Out", "Actual Size",
                "Orchestrator", "Settings", "Quit",
            ]
        )
    }

    // MARK: - Kombo biçimi

    /// Sembol sırası menü çıkarıcısıyla AYNI olmalı: ⌘, ⌃, ⌥, ⇧, sonra tuş.
    func testModifierSymbolOrder() {
        XCTAssertEqual(
            AppCommand.symbols([.shift, .option, .control, .command]),
            ["⌘", "⌃", "⌥", "⇧"]
        )
    }

    func testArrowKeysRenderAsSymbols() {
        XCTAssertEqual(AppCommand.keySymbol(CommandKey.leftArrow), "←")
        XCTAssertEqual(AppCommand.keySymbol(CommandKey.rightArrow), "→")
        XCTAssertEqual(AppCommand.keySymbol("b"), "B")
        XCTAssertEqual(AppCommand.keySymbol(","), ",")
    }

    /// İndeksli komut iki UÇ kombo ile ifade edilir ("⌘1 – ⌘9").
    func testIndexedCommandExposesRangeEndpoints() {
        let projectSwitch = AppCommands.all().first { $0.id == .switchToProjectAtIndex }
        XCTAssertEqual(projectSwitch?.displayCombos, [["⌃", "1"], ["⌃", "9"]])
        let terminalFocus = AppCommands.all().first { $0.id == .focusTerminalAtIndex }
        XCTAssertEqual(terminalFocus?.displayCombos, [["⌘", "1"], ["⌘", "9"]])
    }

    // MARK: - İndeksli kısayol düzeni (karar 62)

    /// Takas YALNIZ iki indeksli ailenin değiştiricilerini yer değiştirir.
    func testSwappedStyleExchangesIndexedModifiers() {
        let swapped = AppCommands.all(.repoOnCommand)
        let projectSwitch = swapped.first { $0.id == .switchToProjectAtIndex }
        XCTAssertEqual(projectSwitch?.displayCombos, [["⌘", "1"], ["⌘", "9"]])
        let terminalFocus = swapped.first { $0.id == .focusTerminalAtIndex }
        XCTAssertEqual(terminalFocus?.displayCombos, [["⌃", "1"], ["⌃", "9"]])
    }

    /// Takas edilmiş tabloda da çakışan kombo yoktur ve ⌘'siz kısayol yine
    /// TEK ailedir (bu kez terminal odağı).
    func testSwappedStyleKeepsTheTableConsistent() {
        var seen: Set<[String]> = []
        for command in AppCommands.all(.repoOnCommand) {
            let combos = command.indexRange.map { range in
                range.map { AppCommand.symbols(command.modifiers) + [String($0)] }
            } ?? command.displayCombos
            for combo in combos {
                XCTAssertTrue(seen.insert(combo).inserted, "çakışan kombo: \(combo.joined())")
            }
            if command.id != .focusTerminalAtIndex {
                XCTAssertTrue(command.modifiers.contains(.command), "\(command.title) ⌘ taşımıyor")
            } else {
                XCTAssertEqual(command.modifiers, [.control], "\(command.title) yalnız ⌃ taşımalı")
            }
        }
    }

    /// Takas kısayolların NE YAPTIĞINI değiştirmez: kimlikler, sıra ve
    /// etiketler aynı kalır — yalnız değiştiriciler yer değiştirir.
    func testSwappedStyleKeepsIdentitiesAndOrder() {
        XCTAssertEqual(
            AppCommands.all(.repoOnCommand).map(\.id),
            AppCommands.all(.repoOnControl).map(\.id)
        )
        XCTAssertEqual(
            AppCommands.reference(.repoOnCommand).map { $0.referenceTitle ?? $0.title },
            AppCommands.reference(.repoOnControl).map { $0.referenceTitle ?? $0.title }
        )
    }

    // MARK: - Menü bölümleri

    func testEverySectionKeepsTableOrder() {
        let fromSections = MenuSection.allCases.flatMap { AppCommands.commands(in: $0) }
        XCTAssertEqual(fromSections.map(\.id), AppCommands.all().map(\.id))
    }
}
