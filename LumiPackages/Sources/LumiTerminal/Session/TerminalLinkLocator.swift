import Foundation
import LumiKit
import SwiftTerm

/// Bir ekran satırının metni ve her UTF-16 biriminin geldiği hücre (karar 116).
/// Geniş karakter iki hücre kaplar; ardındaki boş "devam" hücresi metne girmez.
struct TerminalRowText: Equatable {
    struct Cell: Equatable {
        let col: Int
        let width: Int
    }

    let text: String
    /// `text`'in her UTF-16 birimi için hücre.
    let cells: [Cell]
    let cols: Int

    /// Yumuşak sarma sezgisi: SwiftTerm `isWrapped`'ı dışarı açmaz; sarılan satır
    /// her zaman son sütuna dayanır (geniş karakter sığmadıysa bir eksiğine).
    var reachesEdge: Bool {
        guard let last = lastContentIndex else { return false }
        return cells[last].col + cells[last].width >= cols - 1
    }

    var startsWithContent: Bool {
        guard let first = text.utf16.first else { return false }
        return !TerminalLinkLocator.isBlank(first)
    }

    private var lastContentIndex: Int? {
        let units = Array(text.utf16)
        return units.indices.last { !TerminalLinkLocator.isBlank(units[$0]) }
    }
}

/// Ekrandaki bir link'in tek satırlık parçası.
struct TerminalLinkSpan: Equatable {
    let row: Int
    let columns: Range<Int>
}

/// Tık/hover hücresindeki link adayı: çözümleyiciye giden metin + ekrandaki yeri.
struct TerminalLinkHit: Equatable {
    let text: String
    let spans: [TerminalLinkSpan]
    /// Yol adayı mı (diske sorulmadan link sayılmaz); URL'ler sorulmaz.
    let requiresExistence: Bool
    /// Ayırıcısız dosya adı — diskin cevabı bilinmeden ASLA link sayılmaz.
    let isBareFilename: Bool

    func contains(row: Int, col: Int) -> Bool {
        spans.contains { $0.row == row && $0.columns.contains(col) }
    }
}

/// Hücredeki link adaylarını bulur: satırları mantıksal satıra birleştirir,
/// `TerminalLinkDetector`'ı koşar ve UTF-16 aralıklarını hücrelere geri eşler.
/// Sıra "önce bunu dene" sırasıdır — hangisinin link olduğuna diskin cevabı
/// karar verir (`DropAwareTerminalView`).
enum TerminalLinkLocator {
    /// Bir link'in yukarı/aşağı en fazla kaç satıra taşabileceği.
    static let maxJoinedRows = 32

    static func isBlank(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0
    }

    /// `row` satırındaki `col` hücresini kapsayan adaylar. Önce birleşik
    /// (sarılmış) mantıksal satırın adayları, sonra yalnız o satırınkiler —
    /// sezgi yanlış birleştirdiyse kısa aday diskte yine bulunur.
    static func hits(
        rowCount: Int,
        row target: Int,
        col: Int,
        rowText read: (Int) -> TerminalRowText?
    ) -> [TerminalLinkHit] {
        // Satır sınırları birkaç kez sorulur; SwiftTerm okuması bir kez yapılsın.
        var memo: [Int: TerminalRowText?] = [:]
        func rowText(_ row: Int) -> TerminalRowText? {
            if let cached = memo[row] { return cached }
            let line = read(row)
            memo[row] = line
            return line
        }
        guard let targetRow = rowText(target) else { return [] }
        let (first, last) = joinedBounds(of: target, rowCount: rowCount, rowText: rowText)
        var hits = hitsInLine(rows: first ... last, target: target, col: col, rowText: rowText)
        if first != last {
            hits += hitsInLine(rows: target ... target, target: target, col: col, rowText: { $0 == target ? targetRow : nil })
        }
        var seen: [[TerminalLinkSpan]] = []
        return hits.filter { hit in
            guard !seen.contains(hit.spans) else { return false }
            seen.append(hit.spans)
            return true
        }
    }

    private static func joinedBounds(
        of target: Int, rowCount: Int, rowText: (Int) -> TerminalRowText?
    ) -> (Int, Int) {
        var first = target
        while first > 0, target - first < maxJoinedRows,
              let above = rowText(first - 1), above.reachesEdge,
              rowText(first)?.startsWithContent == true {
            first -= 1
        }
        var last = target
        while last < rowCount - 1, last - target < maxJoinedRows,
              rowText(last)?.reachesEdge == true,
              let below = rowText(last + 1), below.startsWithContent {
            last += 1
        }
        return (first, last)
    }

    private static func hitsInLine(
        rows: ClosedRange<Int>, target: Int, col: Int, rowText: (Int) -> TerminalRowText?
    ) -> [TerminalLinkHit] {
        var text = ""
        var cells: [(row: Int, cell: TerminalRowText.Cell)] = []
        for row in rows {
            guard let line = rowText(row) else { continue }
            // Birleştirilen satırın sonundaki boşluk dolgusu metne girmez.
            let units = row == rows.upperBound ? line.text.utf16.count : contentLength(line)
            text += (line.text as NSString).substring(to: units)
            cells += line.cells.prefix(units).map { (row, $0) }
        }
        guard let offset = cells.firstIndex(where: { $0.row == target && $0.cell.col <= col && col < $0.cell.col + $0.cell.width }),
              !isBlank(Array(text.utf16)[offset]) else { return [] }
        return TerminalLinkDetector.candidates(in: text, at: offset).map { link in
            TerminalLinkHit(
                text: link.text,
                spans: spans(for: link.range, cells: cells),
                requiresExistence: link.requiresExistence,
                isBareFilename: link.kind == .bareFilename
            )
        }
    }

    private static func contentLength(_ line: TerminalRowText) -> Int {
        let units = Array(line.text.utf16)
        return (units.lastIndex { !isBlank($0) } ?? -1) + 1
    }

    private static func spans(
        for range: Range<Int>, cells: [(row: Int, cell: TerminalRowText.Cell)]
    ) -> [TerminalLinkSpan] {
        var spans: [TerminalLinkSpan] = []
        for index in range where index < cells.count {
            let (row, cell) = cells[index]
            let end = cell.col + cell.width
            if let last = spans.last, last.row == row {
                spans[spans.count - 1] = TerminalLinkSpan(
                    row: row, columns: min(last.columns.lowerBound, cell.col) ..< max(last.columns.upperBound, end)
                )
            } else {
                spans.append(TerminalLinkSpan(row: row, columns: cell.col ..< end))
            }
        }
        return spans
    }
}

// MARK: - SwiftTerm okuması

extension TerminalLinkLocator {
    /// Görünür `row` satırının metni (0-tabanlı ekran satırı).
    static func rowText(in terminal: Terminal, row: Int) -> TerminalRowText? {
        guard let line = terminal.getLine(row: row) else { return nil }
        let cols = min(terminal.cols, line.count)
        var text = ""
        var cells: [TerminalRowText.Cell] = []
        var col = 0
        while col < cols {
            let data = line[col]
            let width = Int(data.width)
            // Geniş karakterin ikinci hücresi.
            guard width > 0 else {
                col += 1
                continue
            }
            let character = terminal.getCharacter(for: data)
            let glyph = character == "\u{0}" ? " " : String(character)
            cells += Array(repeating: TerminalRowText.Cell(col: col, width: width), count: glyph.utf16.count)
            text += glyph
            col += width
        }
        return TerminalRowText(text: text, cells: cells, cols: terminal.cols)
    }

    /// OSC 8 (açık) hyperlink: payload'ı tık hücresininkiyle aynı olan bitişik
    /// hücreler aynı satırda tek link'tir.
    static func explicitHit(in terminal: Terminal, row: Int, col: Int) -> (text: String, span: TerminalLinkSpan)? {
        guard let text = terminal.link(at: .screen(Position(col: col, row: row)), mode: .explicitOnly),
              let line = terminal.getLine(row: row),
              let payload = line[col].getPayload() as? String else { return nil }
        let cols = min(terminal.cols, line.count)
        let samePayload = { (index: Int) in (line[index].getPayload() as? String) == payload }
        var start = col
        while start > 0, samePayload(start - 1) { start -= 1 }
        var end = col + 1
        while end < cols, samePayload(end) { end += 1 }
        return (text, TerminalLinkSpan(row: row, columns: start ..< end))
    }
}
