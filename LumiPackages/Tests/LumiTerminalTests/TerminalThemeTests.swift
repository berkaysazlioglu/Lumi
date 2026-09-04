import XCTest
@testable import LumiTerminal

final class TerminalThemeTests: XCTestCase {
    func testLumiHas16ANSIColors() {
        XCTAssertEqual(TerminalTheme.lumi.ansiHex.count, 16)
    }

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

    func testLumiANSIBrightWhite() {
        XCTAssertEqual(TerminalTheme.lumi.ansiHex[15], 0xFFFFFF)
    }

    func testLumiSelectionHasApproximately30PercentAlpha() {
        // 0x4D ≈ 77/255 ≈ 0.302
        let alpha = (TerminalTheme.lumi.selectionHex >> 24) & 0xFF
        XCTAssertEqual(alpha, 0x4D)
    }
}
