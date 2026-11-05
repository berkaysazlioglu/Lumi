import Foundation
import SwiftTerm

/// Hub terminalinin ekran durumunu, boş bir emülatöre beslenince aynı ekranı kuran
/// VT akışına çevirir (karar 143 ek — controller aynasının snapshot'ı).
///
/// `getBufferAsData()` yalnız düz metin ve `\n` verir: renkler, imleç konumu ve modlar
/// (alt-screen, mouse, bracketed paste, uygulama imleci, kaydırma bölgesi) kaybolur;
/// `\n` sütunu sıfırlamadığı için satırlar merdiven gibi kayar ve TUI'nin göreli imleç
/// hareketleri yanlış yere düşer. Bu serileştirici hücreleri SGR'leriyle, satırları
/// `\r\n` ile (sarılmış satırları sarma olarak) yazar, ardından modları ve imleci kurar.
///
/// Alıcı aynı `cols×rows`'a boyutlanmış, sıfırlanmış bir emülatör varsayar
/// (`RemoteTerminalMirror.apply`). Telefona giden düz snapshot değişmez.
public enum TerminalStateSnapshot {
    /// Relay'in 1 MB frame sınırı: base64 (+%33) ve JSON zarfı payıyla ham bütçe.
    public static let defaultByteBudget = 512 * 1024

    private static let esc = "\u{1B}["

    public static func serialize(
        _ terminal: Terminal, isCursorHidden: Bool, byteBudget: Int = defaultByteBudget
    ) -> Data {
        var out = Data()
        let cols = terminal.cols
        let rows = terminal.rows
        if terminal.isCurrentBufferAlternate {
            // Ana ekran yalnız düz metin olarak okunabilir (SwiftTerm ana buffer'ın
            // hücrelerini alt-screen açıkken dışarı vermez); çıkışta görünecek olan budur.
            out.append(plainNormalBuffer(terminal, budget: byteBudget / 2))
            out.append(Data("\(esc)?1049h".utf8))
            for row in 0..<rows {
                out.append(Data("\(esc)\(row + 1);1H".utf8))
                if let line = terminal.getScrollInvariantLine(row: row) {
                    out.append(encode(line, in: terminal, cols: cols, fullWidth: false))
                }
            }
        } else {
            out.append(activeLines(terminal, cols: cols, rows: rows, budget: byteBudget))
        }
        out.append(Data(trailer(terminal, rows: rows, cols: cols, isCursorHidden: isCursorHidden).utf8))
        return out
    }

    // MARK: - Satırlar

    /// Aktif (ana) buffer'ın tüm satırları; bütçe aşılırsa en eskiler düşer ama
    /// görünür `rows` satır her zaman kalır (alıcıda viewport aynı hizaya oturur).
    private static func activeLines(_ terminal: Terminal, cols: Int, rows: Int, budget: Int) -> Data {
        let first = terminal.buffer.totalLinesTrimmed
        var lines: [BufferLine] = []
        while let line = terminal.getScrollInvariantLine(row: first + lines.count) {
            lines.append(line)
        }
        var encoded: [Data] = []
        var total = 0
        for index in stride(from: lines.count - 1, through: 0, by: -1) {
            let continues = index + 1 < lines.count && lines[index + 1].isWrapped
            var chunk = Data()
            if index > 0, !lines[index].isWrapped { chunk.append(Data("\r\n".utf8)) }
            chunk.append(encode(lines[index], in: terminal, cols: cols, fullWidth: continues))
            let keep = lines.count - index <= rows
            guard keep || total + chunk.count <= budget else { break }
            total += chunk.count
            encoded.append(chunk)
        }
        var out = Data()
        for (offset, chunk) in encoded.reversed().enumerated() {
            // Kesilen ilk satırın ayıracı alıcıda boş bir satır açardı.
            out.append(offset == 0 && chunk.starts(with: Data("\r\n".utf8)) ? chunk.dropFirst(2) : chunk)
        }
        return out
    }

    private static func plainNormalBuffer(_ terminal: Terminal, budget: Int) -> Data {
        let text = String(decoding: terminal.getBufferAsData(kind: .normal), as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        var kept: [String] = []
        var total = 0
        for line in lines.reversed() {
            total += line.utf8.count + 2
            guard total <= budget else { break }
            kept.append(line)
        }
        return Data(kept.reversed().joined(separator: "\r\n").utf8)
    }

    /// Bir satırın hücreleri. `fullWidth`: sonraki satır bunun sarması — boşluklar
    /// kırpılmaz ki alıcı da tam genişlikte sarsın.
    private static func encode(_ line: BufferLine, in terminal: Terminal, cols: Int, fullWidth: Bool) -> Data {
        let width = min(cols, line.count)
        let end = fullWidth ? width : trimmedEnd(line, in: terminal, width: width)
        var text = ""
        var current: Attribute?
        var col = 0
        while col < end {
            // Ardından içerik gelen boş hücre dizisi imleç ilerletmeyle atlanır: hücreler
            // alıcıda da boş kalır (boşlukla doldurmak seçim/link algısını değiştirirdi).
            let gap = emptyRun(line, from: col, end: end)
            if gap > 0, col + gap < end {
                text += "\(esc)\(gap)C"
                col += gap
                continue
            }
            let cell = line[col]
            let cellWidth = max(1, Int(cell.width))
            if cell.attribute != current {
                text += sgr(cell.attribute)
                current = cell.attribute
            }
            text.append(character(cell, at: col, of: line, in: terminal))
            col += cellWidth
        }
        if let current, current != Attribute.empty { text += "\(esc)0m" }
        return Data(text.utf8)
    }

    private static func emptyRun(_ line: BufferLine, from start: Int, end: Int) -> Int {
        var col = start
        while col < end, !line.hasContent(index: col) { col += 1 }
        return col - start
    }

    /// Hücrenin karakteri; boş (NUL) hücre boşluk olur — NUL alıcıda imleci ilerletmez.
    private static func character(_ cell: CharData, at col: Int, of line: BufferLine, in terminal: Terminal) -> Character {
        guard line.hasContent(index: col) else { return " " }
        let character = terminal.getCharacter(for: cell)
        return character == "\u{0}" ? " " : character
    }

    /// Sondaki varsayılan biçimli boş hücreler yazılmaz; zemini boyalı boşluklar kalır.
    private static func trimmedEnd(_ line: BufferLine, in terminal: Terminal, width: Int) -> Int {
        var end = width
        while end > 0 {
            let cell = line[end - 1]
            let isBlank = character(cell, at: end - 1, of: line, in: terminal) == " "
            guard isBlank, isDefault(cell.attribute.bg),
                  !cell.attribute.style.contains(.inverse) else { break }
            end -= 1
        }
        return end
    }

    /// SwiftTerm boş hücrelerde zemini `.defaultColor` olarak tutar; `.defaultInvertedColor`
    /// da varsayılan zemindir.
    private static func isDefault(_ color: Attribute.Color) -> Bool {
        color == .defaultColor || color == .defaultInvertedColor
    }

    // MARK: - SGR

    static func sgr(_ attribute: Attribute) -> String {
        var codes = ["0"]
        let style = attribute.style
        if style.contains(.bold) { codes.append("1") }
        if style.contains(.dim) { codes.append("2") }
        if style.contains(.italic) { codes.append("3") }
        if style.contains(.underline) { codes.append("4") }
        if style.contains(.blink) { codes.append("5") }
        if style.contains(.inverse) { codes.append("7") }
        if style.contains(.invisible) { codes.append("8") }
        if style.contains(.crossedOut) { codes.append("9") }
        codes += color(attribute.fg, base: 30, bright: 90, extended: 38)
        codes += color(attribute.bg, base: 40, bright: 100, extended: 48)
        return "\(esc)\(codes.joined(separator: ";"))m"
    }

    private static func color(_ color: Attribute.Color, base: Int, bright: Int, extended: Int) -> [String] {
        switch color {
        case .ansi256(let code) where code < 8: return ["\(base + Int(code))"]
        case .ansi256(let code) where code < 16: return ["\(bright + Int(code) - 8)"]
        case .ansi256(let code): return ["\(extended)", "5", "\(code)"]
        case .trueColor(let r, let g, let b): return ["\(extended)", "2", "\(r)", "\(g)", "\(b)"]
        case .defaultColor, .defaultInvertedColor: return []
        }
    }

    // MARK: - Modlar + imleç

    private static func trailer(_ terminal: Terminal, rows: Int, cols: Int, isCursorHidden: Bool) -> String {
        let buffer = terminal.buffer
        var out = "\(esc)0m"
        if buffer.scrollTop != 0 || buffer.scrollBottom != rows - 1 {
            out += "\(esc)\(buffer.scrollTop + 1);\(buffer.scrollBottom + 1)r"
        }
        if terminal.applicationCursor { out += "\(esc)?1h" }
        if terminal.bracketedPasteMode { out += "\(esc)?2004h" }
        if let mouse = mouseMode(terminal.mouseMode) {
            // Kodlama (SGR/utf8) SwiftTerm'de okunamıyor; Claude Code ve modern TUI'ler SGR ister.
            out += "\(esc)?\(mouse)h\(esc)?1006h"
        }
        let y = min(max(buffer.y, 0), rows - 1)
        let x = min(max(buffer.x, 0), cols - 1)
        out += "\(esc)\(y + 1);\(x + 1)H"
        if isCursorHidden { out += "\(esc)?25l" }
        return out
    }

    private static func mouseMode(_ mode: Terminal.MouseMode) -> Int? {
        switch mode {
        case .off: nil
        case .x10: 9
        case .vt200: 1000
        case .buttonEventTracking: 1002
        case .anyEvent: 1003
        }
    }
}
