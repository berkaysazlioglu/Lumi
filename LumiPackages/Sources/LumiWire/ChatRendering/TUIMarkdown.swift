import Foundation

/// Block structure of assistant markdown, as the Claude Code TUI draws it
/// (headings in bold, `-` / `1.` list markers kept, tables as box-drawn grids,
/// fenced code as a monospaced block). Inline markup stays inside the text and
/// is styled by the view via `chatInlineAttributed`.
public enum TUIMarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `depth` 0 = top level; `marker` is `-` or the ordinal (`1.`).
    case listItem(depth: Int, marker: String, text: String)
    case quote(String)
    case code(language: String?, body: String)
    case table(header: [String], rows: [[String]])
    case rule
}

/// Splits markdown into TUI blocks. Unterminated fences (streaming) still form
/// a code block; blank lines only separate blocks.
public func tuiMarkdownBlocks(_ text: String) -> [TUIMarkdownBlock] {
    var parser = TUIMarkdownParser(lines: text.components(separatedBy: "\n"))
    return parser.parse()
}

private struct TUIMarkdownParser {
    let lines: [String]
    var index = 0
    var blocks: [TUIMarkdownBlock] = []
    var paragraph: [String] = []

    /// Spaces per list nesting level.
    private static let listIndentWidth = 2

    init(lines: [String]) { self.lines = lines }

    mutating func parse() -> [TUIMarkdownBlock] {
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph(); parseFence(opening: trimmed)
            } else if trimmed.isEmpty {
                flushParagraph(); index += 1
            } else if let heading = Self.heading(trimmed) {
                flushParagraph(); blocks.append(heading); index += 1
            } else if Self.isRule(trimmed) {
                flushParagraph(); blocks.append(.rule); index += 1
            } else if trimmed.hasPrefix(">") {
                flushParagraph(); parseQuote()
            } else if isTableStart() {
                flushParagraph(); parseTable()
            } else if let item = Self.listItem(line) {
                flushParagraph(); blocks.append(item); index += 1; appendContinuations()
            } else {
                paragraph.append(trimmed); index += 1
            }
        }
        flushParagraph()
        return blocks
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph.removeAll()
    }

    private mutating func parseFence(opening: String) {
        let language = opening.dropFirst(3).trimmingCharacters(in: .whitespaces)
        var body: [String] = []
        index += 1
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            body.append(lines[index]); index += 1
        }
        if index < lines.count { index += 1 }   // closing fence
        blocks.append(.code(language: language.isEmpty ? nil : language, body: body.joined(separator: "\n")))
    }

    private mutating func parseQuote() {
        var quoted: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            quoted.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }
        blocks.append(.quote(quoted.joined(separator: "\n")))
    }

    /// Indented, non-marker lines right after a list item belong to it.
    private mutating func appendContinuations() {
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, line.hasPrefix(" "), Self.listItem(line) == nil,
                  case let .listItem(depth, marker, text)? = blocks.last else { return }
            blocks[blocks.count - 1] = .listItem(depth: depth, marker: marker, text: text + "\n" + trimmed)
            index += 1
        }
    }

    private func isTableStart() -> Bool {
        guard index + 1 < lines.count else { return false }
        let head = lines[index].trimmingCharacters(in: .whitespaces)
        return head.hasPrefix("|") && Self.isTableSeparator(lines[index + 1])
    }

    private mutating func parseTable() {
        let header = Self.cells(lines[index])
        index += 2
        var rows: [[String]] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { break }
            rows.append(Self.cells(trimmed)); index += 1
        }
        blocks.append(.table(header: header, rows: rows))
    }

    // MARK: Line classifiers

    private static func heading(_ trimmed: String) -> TUIMarkdownBlock? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func listItem(_ line: String) -> TUIMarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " }).count
        let body = line.dropFirst(indent)
        let depth = indent / listIndentWidth
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            return .listItem(depth: depth, marker: "-", text: body.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        let digits = body.prefix(while: \.isNumber)
        let afterDigits = body.dropFirst(digits.count)
        guard !digits.isEmpty, let dot = afterDigits.first, dot == "." || dot == ")",
              afterDigits.dropFirst().first == " " else { return nil }
        return .listItem(depth: depth, marker: "\(digits).",
                         text: afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Box-drawn table lines (Claude TUI style). Cells are reduced to their plain
/// text (inline markup removed) so the monospaced columns line up; short rows
/// are padded with empty cells.
public func tuiTableLines(header: [String], rows: [[String]]) -> [String] {
    let columnCount = ([header] + rows).map(\.count).max() ?? 0
    guard columnCount > 0 else { return [] }
    func plain(_ row: [String]) -> [String] {
        (0..<columnCount).map { $0 < row.count ? chatPlainText(row[$0]) : "" }
    }
    let head = plain(header)
    let body = rows.map(plain)
    let widths = (0..<columnCount).map { column in
        ([head] + body).map { $0[column].count }.max() ?? 0
    }
    func border(_ left: String, _ mid: String, _ right: String) -> String {
        left + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: mid) + right
    }
    func line(_ cells: [String]) -> String {
        "│" + zip(cells, widths).map { cell, width in
            " " + cell + String(repeating: " ", count: width - cell.count) + " "
        }.joined(separator: "│") + "│"
    }
    return [border("┌", "┬", "┐"), line(head), border("├", "┼", "┤")]
        + body.map(line)
        + [border("└", "┴", "┘")]
}

/// Inline markdown reduced to its visible characters (`**a**` → `a`).
public func chatPlainText(_ inline: String) -> String {
    String(chatInlineAttributed(inline).characters)
}

/// Tool output folded the way the TUI does: the first `limit` lines, then a
/// `… +N lines` hint. Trailing blank lines don't count.
public struct TUIFoldedOutput: Sendable, Equatable {
    public let visible: String
    public let hiddenLineCount: Int

    public init(_ output: String, limit: Int) {
        var lines = output.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        visible = lines.prefix(limit).joined(separator: "\n")
        hiddenLineCount = max(0, lines.count - limit)
    }
}
