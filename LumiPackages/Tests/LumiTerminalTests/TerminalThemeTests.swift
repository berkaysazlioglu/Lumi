import XCTest
@testable import LumiTerminal

final class TerminalThemeTests: XCTestCase {

    // MARK: - preset(id:) davranışı

    func testPresetReturnsKnownThemeByID() {
        let known = ["lumi", "dracula", "one-dark", "nord",
                     "solarized-dark", "solarized-light", "github-light"]
        for id in known {
            let theme = TerminalTheme.preset(id: id)
            XCTAssertEqual(theme.id, id, "preset(id:) '\(id)' için yanlış tema döndürdü")
        }
    }

    func testPresetFallsBackToLumiForUnknownID() {
        // Arrange
        let unknownIDs = ["", "unknown", "LUMI", "one_dark", "github"]

        for id in unknownIDs {
            // Act
            let theme = TerminalTheme.preset(id: id)

            // Assert
            XCTAssertEqual(theme.id, "lumi",
                           "Bilinmeyen id '\(id)' için .lumi beklendi, '\(theme.id)' döndü")
        }
    }

    // MARK: - all dizisinin benzersiz id'leri

    func testAllPresetsHaveUniqueIDs() {
        // Arrange
        let ids = TerminalTheme.all.map(\.id)

        // Act
        let uniqueIDs = Set(ids)

        // Assert
        XCTAssertEqual(ids.count, uniqueIDs.count,
                       "TerminalTheme.all içinde tekrar eden id var: \(ids)")
    }

    func testAllContainsExpectedCount() {
        XCTAssertEqual(TerminalTheme.all.count, 7)
    }

    func testAllContainsLumiAsFirst() {
        XCTAssertEqual(TerminalTheme.all.first?.id, "lumi")
    }

    // MARK: - Her temanın ANSI paleti 16 renk içermelidir

    func testAllPresetsHave16ANSIColors() {
        for theme in TerminalTheme.all {
            XCTAssertEqual(theme.ansiHex.count, 16,
                           "'\(theme.id)' temasının ANSI paleti \(theme.ansiHex.count) renk içeriyor, 16 beklendi")
        }
    }

    // MARK: - Lumi teması orijinal hex değerlerini korumalıdır

    func testLumiBackgroundHex() {
        XCTAssertEqual(TerminalTheme.lumi.backgroundHex, 0x12121F)
    }

    func testLumiForegroundHex() {
        XCTAssertEqual(TerminalTheme.lumi.foregroundHex, 0xE2E2F0)
    }

    func testLumiCursorHex() {
        XCTAssertEqual(TerminalTheme.lumi.cursorHex, 0xA78BFA)
    }

    func testLumiCursorTextMatchesBackground() {
        XCTAssertEqual(TerminalTheme.lumi.cursorTextHex, TerminalTheme.lumi.backgroundHex)
    }

    func testLumiANSIBlack() {
        XCTAssertEqual(TerminalTheme.lumi.ansiHex[0], 0x0A0A12)
    }

    func testLumiANSIRed() {
        XCTAssertEqual(TerminalTheme.lumi.ansiHex[1], 0xF87171)
    }

    func testLumiANSIBlue() {
        XCTAssertEqual(TerminalTheme.lumi.ansiHex[4], 0xA78BFA)
    }

    func testLumiANSIBrightWhite() {
        XCTAssertEqual(TerminalTheme.lumi.ansiHex[15], 0xFFFFFF)
    }

    // MARK: - Identifiable uyumu

    func testIDPropertyMatchesExpectedValue() {
        XCTAssertEqual(TerminalTheme.lumi.id, "lumi")
        XCTAssertEqual(TerminalTheme.preset(id: "dracula").id, "dracula")
        XCTAssertEqual(TerminalTheme.preset(id: "nord").id, "nord")
    }

    // MARK: - Equatable uyumu

    func testSamePresetIsEqual() {
        XCTAssertEqual(TerminalTheme.lumi, TerminalTheme.lumi)
        XCTAssertEqual(TerminalTheme.preset(id: "nord"), TerminalTheme.preset(id: "nord"))
    }

    func testDifferentPresetsAreNotEqual() {
        XCTAssertNotEqual(TerminalTheme.lumi, TerminalTheme.preset(id: "dracula"))
    }

    // MARK: - previewColors

    func testPreviewColorsCountIsNine() {
        // background + foreground + cursor + 6 ANSI
        for theme in TerminalTheme.all {
            XCTAssertEqual(theme.previewColors.count, 9,
                           "'\(theme.id)' previewColors sayısı 9 olmalı")
        }
    }

    func testPreviewColorsStartsWithBackground() {
        let theme = TerminalTheme.lumi
        XCTAssertEqual(theme.previewColors[0], theme.backgroundHex)
    }

    func testPreviewColorsSecondIsForeground() {
        let theme = TerminalTheme.lumi
        XCTAssertEqual(theme.previewColors[1], theme.foregroundHex)
    }

    // MARK: - Selection rengi alpha kanalı

    func testSelectionHexAlphaIsNonZero() {
        for theme in TerminalTheme.all {
            let alpha = (theme.selectionHex >> 24) & 0xFF
            XCTAssertGreaterThan(alpha, 0,
                                 "'\(theme.id)' selection rengi alpha=0 (tamamen şeffaf)")
        }
    }

    func testLumiSelectionHasApproximately30PercentAlpha() {
        // Lumi selection: 0x4D ≈ 77/255 ≈ 0.302 — ~30%
        let alpha = (TerminalTheme.lumi.selectionHex >> 24) & 0xFF
        XCTAssertEqual(alpha, 0x4D)
    }

    // MARK: - name alanı boş değil

    func testAllPresetsHaveNonEmptyName() {
        for theme in TerminalTheme.all {
            XCTAssertFalse(theme.name.isEmpty,
                           "'\(theme.id)' temasının adı boş")
        }
    }
}
