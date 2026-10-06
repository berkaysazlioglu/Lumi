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

    /// Elle sarma sezgisi (Claude gibi TUI'ler uzun yolu kendileri alt satıra
    /// kırar ve devamını girintiyle başlatır): satırın içeriği bir yol
    /// karakteriyle bitiyor / başlıyor mu.
    var endsWithPathFragment: Bool {
        guard let last = lastContentIndex else { return false }
        return TerminalLinkLocator.isPathFragment(Array(text.utf16)[last])
    }

    var startsWithPathFragment: Bool {
        guard let first = firstContentIndex else { return false }
        return TerminalLinkLocator.isPathFragment(Array(text.utf16)[first])
    }

    /// İçeriğin tamamı yol karakteri mi (elle sarılmış yolun ortadaki satırı).
    var isWhollyPathFragment: Bool {
        guard let first = firstContentIndex, let last = lastContentIndex else { return false }
        let units = Array(text.utf16)
        return units[first ... last].allSatisfy(TerminalLinkLocator.isPathFragment)
    }

    /// `col` hücresindeki yol parçası satır içeriğinin başına / sonuna dayanıyor mu.
    func pathFragmentTouchesBounds(at col: Int) -> (start: Bool, end: Bool) {
        let units = Array(text.utf16)
        guard let index = cells.firstIndex(where: { $0.col <= col && col < $0.col + $0.width }),
              TerminalLinkLocator.isPathFragment(units[index]),
              let first = firstContentIndex, let last = lastContentIndex else { return (false, false) }
        var start = index
        while start > first, TerminalLinkLocator.isPathFragment(units[start - 1]) { start -= 1 }
        var end = index
        while end < last, TerminalLinkLocator.isPathFragment(units[end + 1]) { end += 1 }
        return (start == first, end == last)
    }

    /// İçeriğin bittiği sütun (sondaki boşluk dolgusu hariç).
    var contentEndColumn: Int {
        guard let last = lastContentIndex else { return 0 }
        return cells[last].col + cells[last].width
    }

    var firstContentIndex: Int? {
        let units = Array(text.utf16)
        return units.indices.first { !TerminalLinkLocator.isBlank(units[$0]) }
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
    /// Elle sarmada yukarı/aşağı bakılan satır sayısı — her başlangıç/bitiş
    /// çifti ayrı aday olduğu için yumuşak sarmadan dar tutulur.
    static let maxHardWrappedRows = 6

    /// Orca `HARD_WRAPPED_PATH_FRAGMENT_PATTERN`: `[A-Za-z0-9._~@%+=:,/\\-]`.
    private static let pathFragmentUnits: Set<UInt16> = Set("._~@%+=:,/\\-".utf16)

    static func isBlank(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0
    }

    static func isPathFragment(_ unit: UInt16) -> Bool {
        (0x30 ... 0x39).contains(unit) || (0x41 ... 0x5A).contains(unit)
            || (0x61 ... 0x7A).contains(unit) || pathFragmentUnits.contains(unit)
    }

    /// `row` satırındaki `col` hücresini kapsayan adaylar, denenme sırasıyla:
    /// yumuşak sarılmış (son sütuna dayanan) mantıksal satır, elle sarılmış
    /// (Claude'un girintili devam satırları) birleşimler, son olarak yalnız o
    /// satır — sezgi yanlış birleştirdiyse kısa aday diskte yine bulunur.
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
        guard rowText(target) != nil else { return [] }
        let (first, last) = joinedBounds(of: target, rowCount: rowCount, rowText: rowText)
        var hits = first != last ? hitsInLine(rows: first ... last, target: target, col: col, rowText: rowText) : []
        hits += hardWrappedHits(rowCount: rowCount, target: target, col: col, rowText: rowText)
        hits += hitsInLine(rows: target ... target, target: target, col: col, rowText: rowText)
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

    /// Elle sarılmış yol adayları: hedef satırdan yukarı/aşağı, sınırı yol
    /// karakterleriyle buluşan satırlar girintileri atılarak birleştirilir. Her
    /// (başlangıç, bitiş) çifti bir adaydır — üstteki düzyazı satırı ya da alttaki
    /// "Done" da yol karakteriyle bitip başlayabilir. Yalnız diske sorulan
    /// adaylar kalır; URL ise yalnız üst satırlar sağ kenara yakın bittiyse
    /// (SwiftTerm'in eski Ghostty sezgisi: son `max(2, cols/5)` sütun).
    private static func hardWrappedHits(
        rowCount: Int, target: Int, col: Int, rowText: (Int) -> TerminalRowText?
    ) -> [TerminalLinkHit] {
        // Hover her hücre değişiminde koşar: imlecin altındaki parça satır
        // sınırına dayanmıyorsa birleştirmenin değiştireceği bir şey yoktur.
        guard let touches = rowText(target)?.pathFragmentTouchesBounds(at: col) else { return [] }
        var first = target
        while touches.start, first > 0, target - first < maxHardWrappedRows,
              first == target || rowText(first)?.isWhollyPathFragment == true,
              rowText(first - 1)?.endsWithPathFragment == true,
              rowText(first)?.startsWithPathFragment == true {
            first -= 1
        }
        var last = target
        while touches.end, last < rowCount - 1, last - target < maxHardWrappedRows,
              last == target || rowText(last)?.isWhollyPathFragment == true,
              rowText(last)?.endsWithPathFragment == true,
              rowText(last + 1)?.startsWithPathFragment == true {
            last += 1
        }
        guard first != last else { return [] }
        var hits: [TerminalLinkHit] = []
        for start in first ... target {
            for end in (target ... last).reversed() where start != end {
                hits += hitsInLine(rows: start ... end, target: target, col: col, trimsIndent: true, rowText: rowText)
                    .filter { $0.requiresExistence || reachesNearEdge($0, rowText: rowText) }
            }
        }
        return hits.sorted { $0.spans.count > $1.spans.count }
    }

    private static func reachesNearEdge(_ hit: TerminalLinkHit, rowText: (Int) -> TerminalRowText?) -> Bool {
        hit.spans.dropLast().allSatisfy { span in
            guard let line = rowText(span.row) else { return false }
            return line.contentEndColumn >= line.cols - max(2, line.cols / 5)
        }
    }

    private static func hitsInLine(
        rows: ClosedRange<Int>, target: Int, col: Int, trimsIndent: Bool = false,
        rowText: (Int) -> TerminalRowText?
    ) -> [TerminalLinkHit] {
        var text = ""
        var cells: [(row: Int, cell: TerminalRowText.Cell)] = []
        for row in rows {
            guard let line = rowText(row) else { continue }
            // Birleştirilen satırın sonundaki boşluk dolgusu metne girmez; elle
            // sarmada devam satırının girintisi de girmez.
            let end = row == rows.upperBound ? line.text.utf16.count : contentLength(line)
            let start = trimsIndent && row != rows.lowerBound ? min(end, line.firstContentIndex ?? end) : 0
            text += (line.text as NSString).substring(with: NSRange(location: start, length: end - start))
            cells += line.cells[start ..< end].map { (row, $0) }
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
