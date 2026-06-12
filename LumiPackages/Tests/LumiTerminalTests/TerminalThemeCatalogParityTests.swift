import XCTest
import LumiKit
@testable import LumiTerminal

/// LumiKit'teki UI katalogu (`TerminalThemeCatalog`) ile LumiTerminal'deki otorite
/// (`TerminalTheme.all`) arasında drift'i engeller. UI o modülü import edemediği
/// için katalog ayrı yaşar; bu test ikisinin id/ad/önizleme renklerini eşler.
final class TerminalThemeCatalogParityTests: XCTestCase {

    func testCatalogMatchesAuthoritativeThemesInOrder() {
        let catalog = TerminalThemeCatalog.all
        let themes = TerminalTheme.all

        XCTAssertEqual(catalog.count, themes.count,
                       "Katalog ve otorite tema sayısı farklı")

        for (option, theme) in zip(catalog, themes) {
            XCTAssertEqual(option.id, theme.id, "id eşleşmiyor")
            XCTAssertEqual(option.name, theme.name, "ad eşleşmiyor: \(theme.id)")
            XCTAssertEqual(option.previewHex, theme.previewColors,
                           "önizleme renkleri eşleşmiyor: \(theme.id)")
        }
    }

    func testCatalogPreviewHasNineColors() {
        for option in TerminalThemeCatalog.all {
            XCTAssertEqual(option.previewHex.count, 9,
                           "'\(option.id)' önizleme rengi sayısı 9 olmalı")
        }
    }
}
