import Foundation
import LumiKit
import SwiftTerm

/// SwiftTerm buffer'ını remote dashboard snapshot'ına çevirir (design/06 §2).
/// Görünür ekran hücre öznitelikleriyle (renk/bold/italik…) koşulara bölünür;
/// scrollback kuyruğu düz metindir. Hiç yazılmamış hücreler (NUL) boşluk olur —
/// TUI'ler kelime aralarını cursor hareketiyle atladığından bu şarttır.
enum TerminalScreenRenderer {
    /// `CharData.getCharacter()` null hücre için NUL döndürür (code 0).
    private static let nullCell: Character = "\u{0}"

    static func snapshot(of terminal: Terminal, theme: TerminalTheme) -> TerminalScreenSnapshot {
        TerminalScreenSnapshot(
            history: historyText(of: terminal),
            screen: screenLines(of: terminal, theme: theme)
        )
    }

    // MARK: - Scrollback kuyruğu (düz metin)

    /// Buffer'ın tamamından görünür ekran satırları düşülmüş hali — ekran
    /// stilli bölümde ayrıca verilir, çift göstermemek için burada yoktur.
    static func historyText(of terminal: Terminal) -> String {
        guard let text = String(data: terminal.getBufferAsData(), encoding: .utf8) else {
            return ""
        }
        var lines = text.components(separatedBy: "\n")
        // getBufferAsData her satırdan sonra \n ekler → son eleman boş kalıntıdır
        if lines.last == "" {
            lines.removeLast()
        }
        var history = lines.dropLast(terminal.rows).map(sanitizeHistoryLine)
        while history.last?.isEmpty == true {
            history.removeLast()
        }
        return history.joined(separator: "\n")
    }

    /// NUL hücreler → boşluk; satır sonu boşluk/NUL kuyruğu kırpılır.
    private static func sanitizeHistoryLine(_ line: String) -> String {
        var trimmed = Substring(line)
        while let last = trimmed.last, last == " " || last == nullCell {
            trimmed.removeLast()
        }
        return trimmed.reduce(into: "") { result, character in
            result.append(character == nullCell ? " " : character)
        }
    }

    // MARK: - Görünür ekran (stilli koşular)

    static func screenLines(of terminal: Terminal, theme: TerminalTheme) -> [[TerminalScreenRun]] {
        var lines = (0..<terminal.rows).map { row -> [TerminalScreenRun] in
            guard let line = terminal.getLine(row: row) else { return [] }
            return runs(for: line, cols: terminal.cols, theme: theme)
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    private static func runs(
        for line: BufferLine,
        cols: Int,
        theme: TerminalTheme
    ) -> [TerminalScreenRun] {
        var runs: [TerminalScreenRun] = []
        var text = ""
        var style: ResolvedStyle?

        func flush() {
            guard let current = style, !text.isEmpty else { return }
            runs.append(TerminalScreenRun(
                text: text,
                foreground: current.foreground,
                background: current.background,
                flags: current.flags
            ))
            text = ""
        }

        for col in 0..<min(cols, line.count) {
            let cell = line[col]
            let character = cell.getCharacter()
            // Wide karakterin (CJK/emoji) ikinci hücresi görsel artıktır — atla
            if character == nullCell, col > 0, line[col - 1].width == 2 {
                continue
            }
            let resolved = ResolvedStyle(attribute: cell.attribute, theme: theme)
            if resolved != style {
                flush()
                style = resolved
            }
            text.append(character == nullCell ? " " : character)
        }
        flush()

        // Satır sonundaki stilsiz boşluk koşularını kırp (payload)
        while let last = runs.last,
              last.foreground == nil, last.background == nil, last.flags == 0,
              last.text.allSatisfy({ $0 == " " }) {
            runs.removeLast()
        }
        if var last = runs.popLast() {
            if last.foreground == nil, last.background == nil, last.flags == 0 {
                var trimmed = Substring(last.text)
                while trimmed.last == " " { trimmed.removeLast() }
                last = TerminalScreenRun(text: String(trimmed))
            }
            if !last.text.isEmpty {
                runs.append(last)
            }
        }
        return runs
    }
}

/// Hücre özniteliğinin CSS karşılığı; inverse/invisible burada çözülür ki
/// client yalnız düz stil uygulasın.
private struct ResolvedStyle: Equatable {
    let foreground: String?
    let background: String?
    let flags: Int

    init(attribute: Attribute, theme: TerminalTheme) {
        var flags = 0
        let style = attribute.style
        if style.contains(.bold) { flags |= TerminalRunFlag.bold }
        if style.contains(.italic) { flags |= TerminalRunFlag.italic }
        if style.contains(.underline) { flags |= TerminalRunFlag.underline }
        if style.contains(.dim) { flags |= TerminalRunFlag.dim }
        if style.contains(.crossedOut) { flags |= TerminalRunFlag.strikethrough }

        let isBold = style.contains(.bold)
        var fg = Self.css(attribute.fg, theme: theme, isForeground: true, isBold: isBold)
        var bg = Self.css(attribute.bg, theme: theme, isForeground: false, isBold: false)
        // SwiftTerm ile aynı sıra (getAttributedValue): önce renkler çözülür,
        // inverse çözülmüş çiftin swap'ıdır.
        if style.contains(.inverse) {
            let resolvedFg = fg ?? Self.hex(theme.foregroundHex)
            let resolvedBg = bg ?? Self.hex(theme.backgroundHex)
            (fg, bg) = (resolvedBg, resolvedFg)
        }
        if style.contains(.invisible) {
            fg = bg ?? Self.hex(theme.backgroundHex)
        }
        self.foreground = fg
        self.background = bg
        self.flags = flags
    }

    /// SwiftTerm `mapColor` karşılığı: `.defaultColor` = temanın kendi kanalı
    /// (nil → client default'u kullanır), `.defaultInvertedColor` = aynı
    /// kanalın ters rengi.
    private static func css(
        _ color: Attribute.Color,
        theme: TerminalTheme,
        isForeground: Bool,
        isBold: Bool
    ) -> String? {
        switch color {
        case .defaultColor:
            return nil
        case .defaultInvertedColor:
            let base = (isForeground ? theme.foregroundHex : theme.backgroundHex) & 0xFFFFFF
            return hex(0xFFFFFF - base)
        case .trueColor(let red, let green, let blue):
            return String(format: "#%02x%02x%02x", red, green, blue)
        case .ansi256(let code):
            return ansi256CSS(Int(code), theme: theme, isBold: isBold)
        }
    }

    /// 0-15 tema paleti (bold, 0-6'yı parlak varyanta terfi ettirir — SwiftTerm
    /// `useBrightColors` davranışı); 16-231 xterm 6×6×6 küpü; 232-255 gri rampası.
    private static func ansi256CSS(_ code: Int, theme: TerminalTheme, isBold: Bool) -> String {
        if code < 16 {
            let index = (isBold && code < 7) ? code + 8 : code
            guard let paletteHex = theme.ansiHex.indices.contains(index)
                ? theme.ansiHex[index] : theme.ansiHex.last else {
                return hex(0xFFFFFF)
            }
            return hex(paletteHex)
        }
        if code >= 232 {
            let gray = 8 + 10 * (code - 232)
            return String(format: "#%02x%02x%02x", gray, gray, gray)
        }
        let steps = [0, 95, 135, 175, 215, 255]
        let value = code - 16
        let red = steps[(value / 36) % 6]
        let green = steps[(value / 6) % 6]
        let blue = steps[value % 6]
        return String(format: "#%02x%02x%02x", red, green, blue)
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "#%06x", value & 0xFFFFFF)
    }
}
