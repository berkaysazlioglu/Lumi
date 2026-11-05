import Foundation
import SwiftTerm
import Testing
@testable import LumiTerminal

// Controller aynasının snapshot'ı (karar 143 ek): hub emülatörünün durumu VT akışına
// çevrilir; aynı boyuttaki boş bir emülatöre beslenince ekran aynen kurulmalı.

private final class NullDelegate: TerminalDelegate, @unchecked Sendable {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

private let delegate = NullDelegate()

private func makeTerminal(cols: Int = 20, rows: Int = 5) -> Terminal {
    Terminal(delegate: delegate, options: TerminalOptions(cols: cols, rows: rows, scrollback: 200))
}

/// Kaynağı serileştirip boş bir emülatörde yeniden kurar.
private func roundTrip(_ source: Terminal, isCursorHidden: Bool = false,
                       budget: Int = TerminalStateSnapshot.defaultByteBudget) -> (Terminal, Data) {
    let data = TerminalStateSnapshot.serialize(source, isCursorHidden: isCursorHidden, byteBudget: budget)
    let target = makeTerminal(cols: source.cols, rows: source.rows)
    target.feed(byteArray: [UInt8](data))
    return (target, data)
}

/// Aktif buffer'ın satırları: metin + hücre biçimleri + sarma bayrağı.
private func lines(_ terminal: Terminal) -> [String] {
    var result: [String] = []
    let first = terminal.buffer.totalLinesTrimmed
    while let line = terminal.getScrollInvariantLine(row: first + result.count) {
        let attrs = (0..<line.count).map { "\(line[$0].attribute.fg)/\(line[$0].attribute.bg)/\(line[$0].attribute.style.rawValue)" }
        let text = line.translateToString(trimRight: true)
        let styled = attrs.prefix(text.count).joined(separator: ",")
        result.append("\(line.isWrapped ? "↩" : "")\(text)|\(styled)")
    }
    return result
}

struct TerminalStateSnapshotTests {
    @Test func colorsScrollbackAndCursorSurvive() {
        let source = makeTerminal()
        for index in 0..<12 { source.feed(text: "satır \(index)\r\n") }
        source.feed(text: "\u{1B}[1;31mkırmızı\u{1B}[0m \u{1B}[38;5;200mpembe\u{1B}[48;2;10;20;30m zemin\u{1B}[0m")
        source.feed(text: "\u{1B}[2;4H")

        let (target, data) = roundTrip(source)

        #expect(lines(target) == lines(source))
        #expect(target.buffer.x == source.buffer.x)
        #expect(target.buffer.y == source.buffer.y)
        // Her satır sonu satır başına da döner (merdiven yok).
        let bytes = [UInt8](data)
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            #expect(index > 0 && bytes[index - 1] == 0x0D)
        }
    }

    @Test func wrappedLinesStayWrapped() {
        let source = makeTerminal(cols: 10, rows: 4)
        source.feed(text: "0123456789abcdefghij-son\r\nkısa")

        let (target, _) = roundTrip(source)

        #expect(lines(target) == lines(source))
        #expect(lines(target).contains { $0.hasPrefix("↩") })
    }

    @Test func wideCharactersKeepColumns() {
        let source = makeTerminal(cols: 12, rows: 3)
        source.feed(text: "a界b🙂c\u{1B}[2;1Hx")

        let (target, _) = roundTrip(source)

        #expect(lines(target) == lines(source))
        #expect(target.buffer.x == source.buffer.x)
    }

    @Test func alternateScreenModesAndScrollRegionSurvive() {
        let source = makeTerminal()
        source.feed(text: "kabuk geçmişi\r\n$ claude")
        source.feed(text: "\u{1B}[?1049h\u{1B}[?1h\u{1B}[?2004h\u{1B}[?1003h\u{1B}[?1006h\u{1B}[2;4r")
        source.feed(text: "\u{1B}[1;1H\u{1B}[7m başlık \u{1B}[0m\u{1B}[3;5Hgövde")

        let (target, data) = roundTrip(source, isCursorHidden: true)

        #expect(target.isCurrentBufferAlternate)
        #expect(lines(target) == lines(source))
        #expect(target.applicationCursor)
        #expect(target.bracketedPasteMode)
        #expect(target.mouseMode == .anyEvent)
        #expect(target.buffer.scrollTop == 1)
        #expect(target.buffer.scrollBottom == 3)
        #expect(target.buffer.x == source.buffer.x)
        #expect(target.buffer.y == source.buffer.y)
        #expect(String(decoding: data, as: UTF8.self).hasSuffix("\u{1B}[?25l"))

        // Alt-screen'den çıkınca ana ekranın metni görünür.
        target.feed(text: "\u{1B}[?1049l")
        let normal = String(decoding: target.getBufferAsData(), as: UTF8.self)
        #expect(normal.contains("kabuk geçmişi"))
        #expect(normal.contains("$ claude"))
    }

    @Test func budgetDropsOldestLinesButKeepsTheViewport() {
        let source = makeTerminal(cols: 20, rows: 5)
        for index in 0..<150 { source.feed(text: "uzun geçmiş \(index)\r\n") }
        source.feed(text: "son")

        let (target, data) = roundTrip(source, budget: 400)

        #expect(data.count < 400 + 200)
        let visible = (0..<5).map { target.getLine(row: $0)?.translateToString(trimRight: true) }
        let expected = (0..<5).map { source.getLine(row: $0)?.translateToString(trimRight: true) }
        #expect(visible == expected)
        #expect(target.buffer.y == source.buffer.y)
    }

    @Test func plainTerminalHasNoModeNoise() {
        let source = makeTerminal()
        source.feed(text: "merhaba")
        let text = String(decoding: TerminalStateSnapshot.serialize(source, isCursorHidden: false), as: UTF8.self)
        #expect(!text.contains("?1049h"))
        #expect(!text.contains("?2004h"))
        #expect(!text.contains("?25l"))
        #expect(text.hasSuffix("\u{1B}[1;8H"))
    }
}
