import XCTest
import LumiKit
import SwiftTerm
@testable import LumiTerminal

/// `TerminalCursorShape` + blink → SwiftTerm `CursorStyle` eşleme testleri.
final class TerminalCursorStyleTests: XCTestCase {

    // MARK: - Şekil + blink kombinasyonları

    func testBlockBlinkMapsToBlinkBlock() {
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: .block, blink: true),
            .blinkBlock
        )
    }

    func testBlockSteadyMapsToSteadyBlock() {
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: .block, blink: false),
            .steadyBlock
        )
    }

    func testUnderlineBlinkMapsToBlinkUnderline() {
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: .underline, blink: true),
            .blinkUnderline
        )
    }

    func testUnderlineSteadyMapsToSteadyUnderline() {
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: .underline, blink: false),
            .steadyUnderline
        )
    }

    func testBarBlinkMapsToBlinkBar() {
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: .bar, blink: true),
            .blinkBar
        )
    }

    func testBarSteadyMapsToSteadyBar() {
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: .bar, blink: false),
            .steadyBar
        )
    }

    // MARK: - parse() güvenliği (geçersiz string → block)

    func testParseValidShapes() {
        XCTAssertEqual(TerminalCursorShape.parse("block"), .block)
        XCTAssertEqual(TerminalCursorShape.parse("underline"), .underline)
        XCTAssertEqual(TerminalCursorShape.parse("bar"), .bar)
    }

    func testParseInvalidFallsBackToBlock() {
        for raw in ["", "BLOCK", "beam", "line", "unknown", "Block"] {
            XCTAssertEqual(
                TerminalCursorShape.parse(raw), .block,
                "Geçersiz '\(raw)' için .block beklendi"
            )
        }
    }

    func testInvalidStringMapsThroughToSteadyOrBlinkBlock() {
        // Uçtan uca: parse → mapper geçersiz string'i block davranışına çözer
        let shape = TerminalCursorShape.parse("garbage")
        XCTAssertEqual(
            TerminalCursorStyleMapper.swiftTermStyle(shape: shape, blink: true),
            .blinkBlock
        )
    }
}

extension SwiftTerm.CursorStyle: @retroactive Equatable {
    public static func == (lhs: CursorStyle, rhs: CursorStyle) -> Bool {
        switch (lhs, rhs) {
        case (.blinkBlock, .blinkBlock), (.steadyBlock, .steadyBlock),
             (.blinkUnderline, .blinkUnderline), (.steadyUnderline, .steadyUnderline),
             (.blinkBar, .blinkBar), (.steadyBar, .steadyBar):
            return true
        default:
            return false
        }
    }
}
