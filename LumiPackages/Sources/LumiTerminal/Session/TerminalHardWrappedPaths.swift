import Foundation

/// Bir ekran satırının mantıksal satıra katılan parçası: `TerminalRowText.text`
/// içinde UTF-16 aralığı.
struct TerminalRowSegment: Equatable {
    let row: Int
    let range: Range<Int>
}

/// TUI'nin kendisinin kırdığı yollar (karar 117).
///
/// Claude Code gibi ajanlar uzun bir yolu terminalin yumuşak sarmasına
/// bırakmaz; satırı kendisi böler ve devamı çoğu zaman girintiyle başlar,
/// sağ kenara da dayanmaz:
///
///     ⏺ Read(/Users/dev/project/Sources/Lu
///           miKit/Detection/LinkText.swift)
///
/// Burada terminalin "sarıldı" bilgisi yoktur; yol, satırların boşluksuz
/// parçalarından yeniden kurulur. Üretilen her aday yalnız bir tahmindir —
/// hangisinin link olduğuna diskin cevabı karar verir.
enum TerminalHardWrappedPaths {
    /// Hedef satırın en fazla kaç satır yukarısından başlayan, kaç satıra
    /// yayılan yol denenir.
    static let maxRows = 20

    /// Yol parçasında görülebilen karakterler (boşluk, parantez, tırnak yok).
    private static let fragmentUnits: Set<UInt16> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~@%+=:,/\\-".utf16
    )
    private static let incompleteStart = regex(#"^(?:[/\\]|\.{1,2}/|~/|[A-Za-z]:)$"#)
    /// Parça değilse: satır bir yol başlangıcıyla bitiyor mu (`Read /Users/a`).
    private static let trailingPathStart = regex(
        #"(?:^|[\s•*>-])(?:/|\.{1,2}/|[A-Za-z0-9._-]+/)[A-Za-z0-9._~@%+=:,/\\-]*$"#
    )

    /// `row` satırındaki bir hücreyi kapsayabilecek, en az iki satıra yayılan
    /// parça dizileri; çok satırlı olan önce.
    static func candidates(
        target: Int, rowCount: Int, rowText: (Int) -> TerminalRowText?
    ) -> [[TerminalRowSegment]] {
        func fragment(_ row: Int) -> Fragment? {
            guard row >= 0, row < rowCount, let line = rowText(row) else { return nil }
            return Fragment.trimmed(line, row: row)
        }
        var result: [[TerminalRowSegment]] = []
        for startRow in stride(from: target, through: max(0, target - maxRows + 1), by: -1) {
            guard let start = fragment(startRow) else { continue }
            result += candidates(startingAt: start, target: target, fragment: fragment)
        }
        var seen: [[TerminalRowSegment]] = []
        return result
            .filter { candidate in
                guard candidate.count > 1, !seen.contains(candidate) else { return false }
                seen.append(candidate)
                return true
            }
            .enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map(\.element)
    }

    private static func candidates(
        startingAt start: Fragment, target: Int, fragment: (Int) -> Fragment?
    ) -> [[TerminalRowSegment]] {
        let canStartWholeRow = canStart(start.text)
        let startSuffix = start.suffix()
        let canStartBoundary = startSuffix.map { canStart($0.text) || isIncompleteStart($0.text) } ?? false
        // Hover her harekette çağırır; yol başlatamayan satırın devamı okunmaz.
        guard canStartWholeRow || canStartBoundary else { return [] }

        var source = [start]
        for row in start.row + 1 ..< start.row + maxRows {
            guard let next = fragment(row) else { break }
            source.append(next)
            if !isContinuation(next.text) { break }
        }

        var result: [[TerminalRowSegment]] = []
        var lastWholeText: String?
        if canStartWholeRow {
            var parts: [Fragment] = []
            for part in source {
                if part.row > start.row, !isFragment(part.text) { break }
                parts.append(part)
                if part.row >= target {
                    result.append(parts.map(\.segment))
                    lastWholeText = parts.map(\.text).joined()
                }
            }
        }

        guard let startSuffix, canStartBoundary else { return result }
        var boundary = [startSuffix]
        var reachedMixedContinuation = false
        for part in source.dropFirst() {
            if isContinuation(part.text) {
                boundary.append(part)
                continue
            }
            reachedMixedContinuation = true
            // Yalnız ilk karışık satır yolu kapatabilir; ötesi komşu linkleri birleştirir.
            if let prefix = part.prefix(), prefix.text.utf16.count < part.text.utf16.count {
                boundary.append(prefix)
                if part.row >= target, canStart(boundary.map(\.text).joined()) {
                    result.append(boundary.map(\.segment))
                }
            }
            break
        }
        let boundaryText = boundary.map(\.text).joined()
        if !reachedMixedContinuation, isIncompleteStart(startSuffix.text), boundary.count >= 2,
           let last = boundary.last, last.row >= target,
           canStart(boundaryText), lastWholeText != boundaryText {
            result.append(boundary.map(\.segment))
        }
        return result
    }

    // MARK: - Parça kuralları

    static func isPathUnit(_ unit: UInt16) -> Bool {
        fragmentUnits.contains(unit)
    }

    static func isFragment(_ text: String) -> Bool {
        !text.isEmpty
            && text.utf16.allSatisfy(isPathUnit)
            && text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }

    /// Satır, bir kökten ya da göreli önekten hemen sonra bitmiş olabilir.
    static func isIncompleteStart(_ text: String) -> Bool {
        isMatch(incompleteStart, text)
    }

    static func isContinuation(_ text: String) -> Bool {
        isFragment(text) || isIncompleteStart(text)
    }

    static func canStart(_ text: String) -> Bool {
        guard isFragment(text) else { return isMatch(trailingPathStart, text) }
        return text.contains("/") || text.contains("\\")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Geçersiz hard-wrap deseni: \(pattern) — \(error)")
        }
    }

    private static func isMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }
}

/// Bir satırın boşluksuz bölümü (ya da onun baş/son yol parçası).
private struct Fragment {
    let row: Int
    let range: Range<Int>
    let text: String

    var segment: TerminalRowSegment { TerminalRowSegment(row: row, range: range) }

    /// Satırın baştaki/sondaki boşluklar atılmış hâli; boş satırda `nil`.
    static func trimmed(_ line: TerminalRowText, row: Int) -> Fragment? {
        let units = Array(line.text.utf16)
        guard let first = units.firstIndex(where: { !TerminalLinkLocator.isBlank($0) }),
              let last = units.lastIndex(where: { !TerminalLinkLocator.isBlank($0) }) else { return nil }
        return Fragment(row: row, range: first ..< last + 1, units: units)
    }

    private init(row: Int, range: Range<Int>, units: [UInt16]) {
        self.row = row
        self.range = range
        self.text = String(decoding: units[range], as: UTF16.self)
    }

    private init(row: Int, range: Range<Int>, text: String) {
        self.row = row
        self.range = range
        self.text = text
    }

    /// Sondaki yol karakteri koşusu (`Read(/a/b` → `/a/b`).
    func suffix() -> Fragment? {
        let units = Array(text.utf16)
        var start = units.count
        while start > 0, TerminalHardWrappedPaths.isPathUnit(units[start - 1]) { start -= 1 }
        return slice(units, start ..< units.count)
    }

    /// Baştaki yol karakteri koşusu (`b/c.swift)` → `b/c.swift`).
    func prefix() -> Fragment? {
        let units = Array(text.utf16)
        var end = 0
        while end < units.count, TerminalHardWrappedPaths.isPathUnit(units[end]) { end += 1 }
        return slice(units, 0 ..< end)
    }

    private func slice(_ units: [UInt16], _ local: Range<Int>) -> Fragment? {
        let text = String(decoding: units[local], as: UTF16.self)
        guard TerminalHardWrappedPaths.isContinuation(text) else { return nil }
        return Fragment(
            row: row,
            range: range.lowerBound + local.lowerBound ..< range.lowerBound + local.upperBound,
            text: text
        )
    }
}
