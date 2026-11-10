import Foundation
import LumiKit
import SwiftTerm

/// Bir terminale dosyadan aktarılan kitty görsellerinin kaydı: kimlik → yol
/// (karar 149). Kaynak `KittyGraphicsFileParser`'dır; kayıt view'da durur
/// çünkü tek okuyucusu tık/hover hit testidir.
struct TerminalKittyImageFiles {
    /// Eski görseller scrollback'te durur; sınır yalnız uzun oturumda belleği tutar.
    static let capacity = 256

    private struct Entry {
        let path: String
        let order: UInt64
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextOrder: UInt64 = 0

    var count: Int { entries.count }

    /// Aynı kimlik yeniden aktarılırsa (Claude Code kimliği yeniden kullanır)
    /// son yol geçerlidir.
    mutating func record(_ file: KittyImageFile) {
        entries[file.imageID] = Entry(path: file.path, order: nextOrder)
        nextOrder += 1
        guard entries.count > Self.capacity,
              let oldest = entries.min(by: { $0.value.order < $1.value.order })?.key else { return }
        entries.removeValue(forKey: oldest)
    }

    /// Placeholder hücresinin taşıdığı kimliğin yolu. Hücrenin ön plan rengi
    /// kimliğin alt 24 bitidir (üst bayt ayrı bir diacritic'te taşınır ve
    /// çoğu zaman yoktur); aynı alt 24 biti paylaşan birden çok kayıt varsa en
    /// son aktarılan kazanır.
    func path(forPlaceholderID placeholderID: UInt32) -> String? {
        if let exact = entries[placeholderID] { return exact.path }
        return entries
            .filter { $0.key & TerminalKittyPlaceholder.idMask == placeholderID }
            .max { $0.value.order < $1.value.order }?
            .value.path
    }
}

/// Kitty Unicode placeholder hücrelerinin okunması (karar 149).
///
/// Claude Code görseli `U+10EEEE` karakterli hücrelerle yerleştirir; görselin
/// kimliği hücrenin ön plan renginde taşınır (24-bit renkte RGB baytları,
/// 256 renkte renk kodu). SwiftTerm'in kendi çözücüsü dışarı açık değildir.
enum TerminalKittyPlaceholder {
    static let scalar: UInt32 = 0x10EEEE
    static let idMask: UInt32 = 0xFF_FFFF

    /// Hücre bir placeholder'sa taşıdığı (sıfırdan farklı) kimlik.
    static func imageID(of cell: CharData, in terminal: Terminal) -> UInt32? {
        guard terminal.getCharacter(for: cell).unicodeScalars.first?.value == scalar else { return nil }
        let id: UInt32
        switch cell.attribute.fg {
        case let .trueColor(red, green, blue):
            id = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        case let .ansi256(code):
            id = UInt32(code)
        case .defaultColor, .defaultInvertedColor:
            return nil
        }
        return id == 0 ? nil : id
    }

    /// Ekran hücresi bir placeholder mı — kimliği okunamasa da metin link
    /// aramasına girmez.
    static func isPlaceholder(in terminal: Terminal, row: Int, col: Int) -> Bool {
        guard let line = terminal.getLine(row: row), col >= 0, col < min(terminal.cols, line.count) else {
            return false
        }
        return terminal.getCharacter(for: line[col]).unicodeScalars.first?.value == scalar
    }

    /// `row`/`col`'daki görselin kimliği ve ekrandaki hücreleri: tıklanan
    /// satırdan yukarı ve aşağı, aynı kimliği taşıyan bitişik satırlardaki
    /// placeholder dizileri.
    static func hit(in terminal: Terminal, row: Int, col: Int) -> (imageID: UInt32, spans: [TerminalLinkSpan])? {
        guard let line = terminal.getLine(row: row), col >= 0, col < min(terminal.cols, line.count),
              let id = imageID(of: line[col], in: terminal) else { return nil }
        var spans = runs(of: id, in: terminal, row: row)
        var above = row - 1
        while above >= 0 {
            let found = runs(of: id, in: terminal, row: above)
            guard !found.isEmpty else { break }
            spans = found + spans
            above -= 1
        }
        var below = row + 1
        while below < terminal.rows {
            let found = runs(of: id, in: terminal, row: below)
            guard !found.isEmpty else { break }
            spans += found
            below += 1
        }
        return (id, spans)
    }

    /// Satırda `id`'yi taşıyan bitişik placeholder dizileri.
    private static func runs(of id: UInt32, in terminal: Terminal, row: Int) -> [TerminalLinkSpan] {
        guard let line = terminal.getLine(row: row) else { return [] }
        let cols = min(terminal.cols, line.count)
        var spans: [TerminalLinkSpan] = []
        var start: Int?
        for col in 0 ..< cols {
            if imageID(of: line[col], in: terminal) == id {
                if start == nil { start = col }
            } else if let open = start {
                spans.append(TerminalLinkSpan(row: row, columns: open ..< col))
                start = nil
            }
        }
        if let open = start {
            spans.append(TerminalLinkSpan(row: row, columns: open ..< cols))
        }
        return spans
    }
}
