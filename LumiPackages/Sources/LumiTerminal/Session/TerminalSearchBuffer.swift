import Foundation
import LumiKit
import SwiftTerm

/// Bir eşleşmenin tek satırlık parçası — satır kaydırmadan bağımsızdır
/// (`TerminalSearchPosition.row` ile aynı eksen).
struct TerminalSearchSpan: Equatable {
    let row: Int
    let columns: Range<Int>
}

/// Buffer'da bulunan bir eşleşme.
struct TerminalSearchMatch: Equatable {
    let start: TerminalSearchPosition
    let spans: [TerminalSearchSpan]
}

/// Scrollback dahil tüm buffer'ın mantıksal satırlarını tarayıp eşleşmeleri
/// hücrelere eşler (karar 144).
///
/// Mantıksal satır = SwiftTerm'in `isWrapped` işaretiyle birleşen satırlar:
/// dar terminalde sarılan bir yol ya da cümle de bulunur. Satır metni
/// `BufferLine.generation`'a göre önbelleklenir — çıktı akarken yeniden
/// taramada yalnız değişen satırlar okunur.
@MainActor
final class TerminalSearchBuffer {
    /// Kayıt satır nesnesine bağlıdır; nesne geri dönüştürülüp başka içerik
    /// taşıdığında `generation` artar ve kayıt geçersizleşir.
    private struct Entry {
        weak var line: BufferLine?
        let generation: UInt64
        let cols: Int
        let text: String
        /// Her UTF-16 birimi tek genişlikli tek hücre (ASCII'nin çoğu): hücre
        /// sütunu birimin sırasıdır, eşleme tablosu tutulmaz.
        let isSimple: Bool
    }

    private var cache: [ObjectIdentifier: Entry] = [:]

    /// Görünür alanın kaydırmadan bağımsız satır aralığı.
    static func visibleRows(of terminal: Terminal) -> ClosedRange<Int> {
        let top = terminal.buffer.totalLinesTrimmed + terminal.buffer.yDisp
        return top ... top + max(terminal.rows, 1) - 1
    }

    /// Tüm eşleşmeler, buffer sırasıyla; `limit`'e ulaşınca kesilir.
    func matches(
        for compiled: TerminalSearchMatcher.Compiled,
        in terminal: Terminal,
        limit: Int = TerminalSearchMatcher.matchLimit
    ) -> (matches: [TerminalSearchMatch], isCapped: Bool) {
        var result: [TerminalSearchMatch] = []
        var seen: Set<ObjectIdentifier> = []
        var logical: [(row: Int, entry: Entry)] = []

        /// Biriken mantıksal satırı tarar; `true` → sınır aşıldı, tarama biter.
        /// Sınırın bir fazlası istenir ki "tam 1000" ile "1000'den fazla" ayrışsın.
        func flush() -> Bool {
            defer { logical.removeAll(keepingCapacity: true) }
            guard !logical.isEmpty else { return false }
            let remaining = limit - result.count
            let text = logical.map(\.entry.text).joined()
            let ranges = TerminalSearchMatcher.ranges(in: text, compiled: compiled, limit: remaining + 1)
            for range in ranges.prefix(remaining) {
                if let match = Self.match(for: range, in: logical, terminal: terminal) { result.append(match) }
            }
            return ranges.count > remaining
        }

        var row = terminal.buffer.totalLinesTrimmed
        while let line = terminal.getScrollInvariantLine(row: row) {
            let id = ObjectIdentifier(line)
            seen.insert(id)
            let entry = entry(for: line, id: id, terminal: terminal)
            if !line.isWrapped, flush() {
                prune(keeping: seen)
                return (result, true)
            }
            logical.append((row, entry))
            row += 1
        }
        let capped = flush()
        prune(keeping: seen)
        return (result, capped)
    }

    func reset() {
        cache.removeAll()
    }

    // MARK: - Satır önbelleği

    private func entry(for line: BufferLine, id: ObjectIdentifier, terminal: Terminal) -> Entry {
        if let cached = cache[id], cached.line === line, cached.generation == line.generation,
           cached.cols == terminal.cols {
            return cached
        }
        let rowText = TerminalLinkLocator.rowText(of: line, in: terminal)
        let isSimple = rowText.cells.enumerated().allSatisfy { $0.element.col == $0.offset && $0.element.width == 1 }
        let entry = Entry(
            line: line, generation: line.generation, cols: terminal.cols, text: rowText.text, isSimple: isSimple
        )
        cache[id] = entry
        return entry
    }

    /// Buffer'dan düşen satırların kayıtları bırakılır (scrollback sınırı).
    private func prune(keeping seen: Set<ObjectIdentifier>) {
        guard cache.count > seen.count else { return }
        cache = cache.filter { seen.contains($0.key) }
    }

    // MARK: - Hücre eşlemesi

    /// UTF-16 aralığını satır parçalarına çevirir. Basit olmayan satırın
    /// hücre tablosu yalnız eşleşme ona düştüğünde yeniden okunur.
    private static func match(
        for range: Range<Int>,
        in logical: [(row: Int, entry: Entry)],
        terminal: Terminal
    ) -> TerminalSearchMatch? {
        var spans: [TerminalSearchSpan] = []
        var offset = 0
        for (row, entry) in logical {
            let length = entry.text.utf16.count
            defer { offset += length }
            // Eşleşme bu satır parçasıyla örtüşmüyorsa sınırlar ters düşer;
            // `Range` kurulmadan önce elenir.
            let lower = max(range.lowerBound, offset) - offset
            let upper = min(range.upperBound, offset + length) - offset
            guard lower < upper else { continue }
            let local = lower ..< upper
            guard let columns = columns(for: local, entry: entry, row: row, terminal: terminal) else { return nil }
            spans.append(TerminalSearchSpan(row: row, columns: columns))
        }
        guard let first = spans.first else { return nil }
        return TerminalSearchMatch(
            start: TerminalSearchPosition(row: first.row, col: first.columns.lowerBound),
            spans: spans
        )
    }

    private static func columns(
        for local: Range<Int>, entry: Entry, row: Int, terminal: Terminal
    ) -> Range<Int>? {
        if entry.isSimple { return local }
        guard let line = terminal.getScrollInvariantLine(row: row) else { return nil }
        let cells = TerminalLinkLocator.rowText(of: line, in: terminal).cells
        guard local.upperBound <= cells.count else { return nil }
        let first = cells[local.lowerBound]
        let last = cells[local.upperBound - 1]
        return first.col ..< last.col + last.width
    }
}
