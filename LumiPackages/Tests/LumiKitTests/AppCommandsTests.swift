import XCTest
@testable import LumiKit

/// Komut tablosunun bütünlüğü (refactor 3.5). Menü, dispatcher ve Shortcuts
/// tablosu bu tablodan türediği için buradaki kurallar üçünü birden korur.
final class AppCommandsTests: XCTestCase {
    func testCommandIDsAreUnique() {
        let ids = AppCommands.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "komut kimlikleri benzersiz olmalı")
    }

    /// Her komutun ya bir tuşu ya da bir indeks aralığı vardır — kısayolsuz
    /// komut menüde sessizce kaybolurdu.
    func testEveryCommandCarriesAShortcut() {
        for command in AppCommands.all {
            XCTAssertTrue(
                command.key != nil || command.indexRange != nil,
                "\(command.title) kısayolsuz"
            )
            XCTAssertFalse(command.displayCombos.isEmpty, "\(command.title) kombosuz")
        }
    }

    /// Tüm kısayollar ⌘ taşır (design/03 §2: menü tek kaynak, ⌘'siz kısayol yok).
    func testEveryShortcutUsesCommandModifier() {
        for command in AppCommands.all {
            XCTAssertTrue(
                command.modifiers.contains(.command),
                "\(command.title) ⌘ taşımıyor"
            )
        }
    }

    /// Aynı kombonun iki komuta düşmesi menüde sessiz çakışma yapardı.
    func testNoDuplicateCombosAcrossCommands() {
        var seen: Set<[String]> = []
        for command in AppCommands.all {
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
        let referenced = Set(AppCommands.reference.map(\.id))
        for command in AppCommands.all where command.isSystemStandard {
            XCTAssertFalse(referenced.contains(command.id), "\(command.title) tabloda olmamalı")
        }
        XCTAssertEqual(AppCommands.reference.count, 12, "12 kullanıcı kısayolu")
    }

    func testReferenceIsSortedByReferenceOrder() {
        let orders = AppCommands.reference.map { $0.referenceOrder ?? .max }
        XCTAssertEqual(orders, orders.sorted())
        XCTAssertEqual(Set(orders).count, orders.count, "sıra numaraları benzersiz")
    }

    /// Referans tablosunun gösterdiği etiketler — Settings ekranının paritesi.
    func testReferenceTitlesMatchTheUserFacingList() {
        XCTAssertEqual(
            AppCommands.reference.map { $0.referenceTitle ?? $0.title },
            [
                "New Terminal", "Close Terminal", "Open Repository", "Switch to Tab N",
                "Previous Terminal", "Next Terminal", "Maximize Terminal",
                "Toggle Left Sidebar", "Toggle Right Sidebar", "Focus Mode",
                "Settings", "Quit",
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
        let indexed = AppCommands.all.first { $0.indexRange != nil }
        XCTAssertEqual(indexed?.displayCombos, [["⌘", "1"], ["⌘", "9"]])
    }

    // MARK: - Menü bölümleri

    func testEverySectionKeepsTableOrder() {
        let fromSections = MenuSection.allCases.flatMap(AppCommands.commands(in:))
        XCTAssertEqual(fromSections.map(\.id), AppCommands.all.map(\.id))
    }
}
