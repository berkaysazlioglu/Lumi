import LumiKit
import SwiftTerm
import XCTest
@testable import LumiTerminal

/// Headless SwiftTerm emülatörüne ANSI besleyip renderer çıktısını doğrular.
final class TerminalScreenRendererTests: XCTestCase {
    private final class NullDelegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private var delegate: NullDelegate!

    private func makeTerminal(cols: Int = 40, rows: Int = 5) -> Terminal {
        delegate = NullDelegate()
        let options = TerminalOptions(cols: cols, rows: rows)
        return Terminal(delegate: delegate, options: options)
    }

    private func plainText(of lines: [[TerminalScreenRun]]) -> [String] {
        lines.map { line in line.map(\.text).joined() }
    }

    // MARK: - Boşluk korunumu (NUL hücreler)

    func testCursorMovementGapsBecomeSpaces() {
        let terminal = makeTerminal()
        // "A" yaz, cursor'u 5 sağa taşı (aradaki hücrelere hiç yazılmaz), "B" yaz
        terminal.feed(text: "A\u{1B}[5CB")

        let lines = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)

        XCTAssertEqual(plainText(of: lines), ["A     B"])
    }

    func testAbsoluteCursorPositioningKeepsWordSpacing() {
        let terminal = makeTerminal()
        // TUI tarzı: 1. satır 1. kolona "Denemek", 9. kolona "için:"
        terminal.feed(text: "\u{1B}[1;1HDenemek\u{1B}[1;9Hiçin:")

        let lines = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)

        XCTAssertEqual(plainText(of: lines), ["Denemek için:"])
    }

    // MARK: - Renk ve stil koşuları

    func testAnsiColorProducesThemePaletteRun() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1B}[31mhata\u{1B}[0m sonrası")

        let lines = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)

        XCTAssertEqual(lines.count, 1)
        let runs = lines[0]
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].text, "hata")
        XCTAssertEqual(runs[0].foreground, String(format: "#%06x", TerminalTheme.lumi.ansiHex[1]))
        XCTAssertEqual(runs[1].text, " sonrası")
        XCTAssertNil(runs[1].foreground)
    }

    func testBoldItalicAndTrueColorFlags() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1B}[1;3;38;2;18;52;86mvurgu\u{1B}[0m")

        let lines = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)

        let run = lines[0][0]
        XCTAssertEqual(run.text, "vurgu")
        XCTAssertEqual(run.foreground, "#123456")
        XCTAssertEqual(run.flags & TerminalRunFlag.bold, TerminalRunFlag.bold)
        XCTAssertEqual(run.flags & TerminalRunFlag.italic, TerminalRunFlag.italic)
    }

    func testXterm256CubeAndGrayColors() {
        let terminal = makeTerminal()
        // 196 = saf kırmızı (küp), 244 = orta gri (rampa)
        terminal.feed(text: "\u{1B}[38;5;196mR\u{1B}[38;5;244mG")

        let runs = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)[0]

        XCTAssertEqual(runs[0].foreground, "#ff0000")
        XCTAssertEqual(runs[1].foreground, "#808080")
    }

    func testInverseIsResolvedServerSide() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1B}[7mters\u{1B}[0m")

        let run = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)[0][0]

        XCTAssertEqual(run.foreground, String(format: "#%06x", TerminalTheme.lumi.backgroundHex))
        XCTAssertEqual(run.background, String(format: "#%06x", TerminalTheme.lumi.foregroundHex))
    }

    // MARK: - Scrollback kuyruğu

    func testHistoryExcludesVisibleScreenRows() {
        let terminal = makeTerminal(cols: 20, rows: 3)
        // 6 satır bas: ilk 3'ü scrollback'e itilir, son 3'ü görünür ekrandır
        terminal.feed(text: (1...6).map { "satır \($0)" }.joined(separator: "\r\n"))

        let history = TerminalScreenRenderer.historyText(of: terminal)
        let screen = TerminalScreenRenderer.screenLines(of: terminal, theme: .lumi)

        XCTAssertEqual(history, "satır 1\nsatır 2\nsatır 3")
        XCTAssertEqual(plainText(of: screen), ["satır 4", "satır 5", "satır 6"])
    }

    func testEmptyTerminalProducesEmptySnapshot() {
        let terminal = makeTerminal()

        let snapshot = TerminalScreenRenderer.snapshot(of: terminal, theme: .lumi)

        XCTAssertEqual(snapshot.history, "")
        XCTAssertTrue(snapshot.screen.allSatisfy(\.isEmpty))
    }
}
