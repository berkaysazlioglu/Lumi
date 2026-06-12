import SwiftTerm
import XCTest

/// SwiftTerm scroll-emülasyonu REGRESYON BEKÇİSİ (headless).
///
/// Tarihçe: v1.13.0'da CSI T (reverse scroll) alt-screen'de yalnız ilk kolonu
/// kaydırıyordu (cmdScrollDown'da margin'siz yol eksik + marginRight=0) —
/// Claude Code'da yukarı scroll'da bayat satırların kök nedeni buydu. Pin'li
/// revision (24a68bc, 94b6356 fix'i dahil) bunu düzeltir; bu testler pin
/// güncellenirken davranışın geri gitmediğini garantiler. Kırmızıya dönerlerse
/// suçlu Lumi değil, SwiftTerm revision'ıdır — pin'i değiştirmeden araştır.
final class SwiftTermScrollDiagnosticTests: XCTestCase {
    private final class StubDelegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private var delegate: StubDelegate!

    private func makeAltScreenTerminal(rows: Int = 24, cols: Int = 80) -> Terminal {
        delegate = StubDelegate()
        let options = TerminalOptions(cols: cols, rows: rows)
        let terminal = Terminal(delegate: delegate, options: options)
        terminal.feed(text: "\u{1b}[?1049h") // alt screen + save cursor
        // Satırları tanımlanabilir içerikle doldur: ROW-01..ROW-24
        for row in 1 ... rows {
            terminal.feed(text: String(format: "\u{1b}[%d;1HROW-%02d", row, row))
        }
        return terminal
    }

    private func lineText(_ terminal: Terminal, _ screenRow: Int) -> String {
        guard let line = terminal.getLine(row: screenRow) else { return "<nil>" }
        return line.translateToString(trimRight: true)
    }

    func testCSITScrollDownTamEkran() {
        // CSI T: içerik 1 satır AŞAĞI kayar (yukarı scroll görünümü)
        let terminal = makeAltScreenTerminal()
        terminal.feed(text: "\u{1b}[T")
        XCTAssertEqual(lineText(terminal, 0), "", "üst satır boşalmalı")
        XCTAssertEqual(lineText(terminal, 1), "ROW-01")
        XCTAssertEqual(lineText(terminal, 23), "ROW-23")
    }

    func testCSISScrollUpTamEkran() {
        // CSI S: içerik 1 satır YUKARI kayar (aşağı scroll görünümü — kontrol grubu)
        let terminal = makeAltScreenTerminal()
        terminal.feed(text: "\u{1b}[S")
        XCTAssertEqual(lineText(terminal, 0), "ROW-02")
        XCTAssertEqual(lineText(terminal, 22), "ROW-24")
        XCTAssertEqual(lineText(terminal, 23), "", "alt satır boşalmalı")
    }

    func testReverseIndexUstSatirda() {
        // Cursor üst satırda ESC M (RI) → CSI T ile aynı etki
        let terminal = makeAltScreenTerminal()
        terminal.feed(text: "\u{1b}[1;1H\u{1b}M")
        XCTAssertEqual(lineText(terminal, 0), "", "üst satır boşalmalı")
        XCTAssertEqual(lineText(terminal, 1), "ROW-01")
        XCTAssertEqual(lineText(terminal, 23), "ROW-23")
    }

    func testCSITMarginIcinde() {
        // DECSTBM 5..20 + CSI T: yalnız bölge içi aşağı kayar, dışı sabit
        let terminal = makeAltScreenTerminal()
        terminal.feed(text: "\u{1b}[5;20r\u{1b}[T")
        XCTAssertEqual(lineText(terminal, 0), "ROW-01", "bölge dışı (üst) sabit")
        XCTAssertEqual(lineText(terminal, 3), "ROW-04", "bölge dışı (üst) sabit")
        XCTAssertEqual(lineText(terminal, 4), "", "bölge üstü boşalmalı")
        XCTAssertEqual(lineText(terminal, 5), "ROW-05")
        XCTAssertEqual(lineText(terminal, 19), "ROW-19")
        XCTAssertEqual(lineText(terminal, 20), "ROW-21", "bölge dışı (alt) sabit")
        XCTAssertEqual(lineText(terminal, 23), "ROW-24", "bölge dışı (alt) sabit")
    }

    func testSynchronizedOutputIcindeScrollVeYenidenCizim() {
        // Claude'un gerçek deseni: BSU (2026h) + scroll/yazım + ESU (2026l).
        // ESU sonrası buffer SON durumu yansıtmalı.
        let terminal = makeAltScreenTerminal()
        terminal.feed(text: "\u{1b}[?2026h") // BSU
        terminal.feed(text: "\u{1b}[T")      // içerik 1 aşağı
        terminal.feed(text: "\u{1b}[1;1HNEW-TOP")
        terminal.feed(text: "\u{1b}[?2026l") // ESU
        XCTAssertEqual(lineText(terminal, 0), "NEW-TOP")
        XCTAssertEqual(lineText(terminal, 1), "ROW-01")
        XCTAssertEqual(lineText(terminal, 23), "ROW-23")
    }

    func testArdisikCokluCSIT() {
        // Hızlı yukarı scroll burst'ü: 5 ardışık CSI T
        let terminal = makeAltScreenTerminal()
        for _ in 0 ..< 5 {
            terminal.feed(text: "\u{1b}[T")
        }
        for row in 0 ..< 5 {
            XCTAssertEqual(lineText(terminal, row), "", "ilk 5 satır boş olmalı (satır \(row))")
        }
        XCTAssertEqual(lineText(terminal, 5), "ROW-01")
        XCTAssertEqual(lineText(terminal, 23), "ROW-19")
    }
}
