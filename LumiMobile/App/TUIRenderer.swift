import UIKit
import LumiMobileKit

/// A rendered stretch of the transcript: wrapping text, or a no-wrap block
/// (code / table) that scrolls horizontally like a wide terminal line.
enum TUIPiece {
    case text(NSAttributedString)
    case wide(NSAttributedString, indentCells: Int)
}

/// Builds Claude-TUI-looking attributed text: `⏺ ` hanging indent, inline
/// code in Claude's "permission" blue, bold/italic as font traits, headings
/// bold (H1 also italic + underlined), `-` / `1.` list markers kept.
struct TUIRenderer {
    let style: TUIStyle

    /// The TUI's `⏺`. U+23FA isn't in the terminal fonts and iOS falls back to
    /// the color emoji (losing the green/red tool state), so it's `●`.
    static let bulletGlyph = "●"
    /// Cells of the `⏺ ` / `> ` gutter.
    static let gutterCells = 2
    /// Gap between blocks, in lines.
    private static let blockGapLines: CGFloat = 0.5
    private static let ruleWidthCells = 24

    private var lineHeight: CGFloat { style.font().lineHeight }

    // MARK: Assistant prose

    func assistant(_ markdown: String) -> [TUIPiece] {
        var pieces: [TUIPiece] = []
        var text = NSMutableAttributedString()
        func flushText() {
            if text.length > 0 { pieces.append(.text(text)); text = NSMutableAttributedString() }
        }
        for (index, block) in tuiMarkdownBlocks(markdown).enumerated() {
            let isFirst = index == 0
            switch block {
            case let .code(_, body):
                flushText()
                pieces.append(.wide(plain(body, color: TUIColors.text), indentCells: Self.gutterCells))
            case let .table(header, rows):
                flushText()
                let lines = tuiTableLines(header: header, rows: rows).joined(separator: "\n")
                pieces.append(.wide(plain(lines, color: TUIColors.text), indentCells: Self.gutterCells))
            default:
                if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
                text.append(render(block, isFirst: isFirst && pieces.isEmpty))
            }
        }
        flushText()
        if pieces.isEmpty { pieces = [.text(bullet(color: TUIColors.text))] }
        if case .wide? = pieces.first {
            // The message opens with a code block/table: the bullet stands alone.
            pieces.insert(.text(bullet(color: TUIColors.text)), at: 0)
        }
        return pieces
    }

    private func render(_ block: TUIMarkdownBlock, isFirst: Bool) -> NSAttributedString {
        let line = NSMutableAttributedString()
        if isFirst { line.append(bullet(color: TUIColors.text)) }
        var paragraph = hangingStyle(firstCells: isFirst ? 0 : Self.gutterCells, restCells: Self.gutterCells)
        switch block {
        case let .heading(level, text):
            line.append(inline(text, bold: true, italic: level == 1, underline: level == 1))
        case let .paragraph(text):
            line.append(inline(text))
        case let .listItem(depth, marker, text):
            let first = Self.gutterCells + depth * Self.gutterCells
            if !isFirst { paragraph = hangingStyle(firstCells: first, restCells: first + marker.count + 1) }
            line.append(plain(marker + " ", color: TUIColors.text))
            line.append(inline(text))
        case let .quote(text):
            line.append(plain("▎ ", color: TUIColors.dim))
            line.append(inline(text, italic: true, color: TUIColors.dim))
        case .rule:
            line.append(plain(String(repeating: "─", count: Self.ruleWidthCells), color: TUIColors.dim))
        case .code, .table:
            break
        }
        if !isFirst { paragraph.paragraphSpacingBefore = lineHeight * Self.blockGapLines }
        line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
        return line
    }

    // MARK: User prompt / tools

    func user(_ text: String) -> NSAttributedString {
        let line = NSMutableAttributedString(attributedString: plain("> ", color: TUIColors.dim))
        line.append(plain(text, color: TUIColors.text))
        line.addAttribute(.paragraphStyle, value: hangingStyle(firstCells: 0, restCells: Self.gutterCells),
                          range: NSRange(location: 0, length: line.length))
        return line
    }

    /// `⏺ Name(preview)` — the dot is green/red once the result lands, dim while running.
    func toolCall(name: String, preview: String, result: TUIToolResult?) -> NSAttributedString {
        let dot: UIColor = result.map { $0.isError ? TUIColors.error : TUIColors.success } ?? TUIColors.dim
        let line = NSMutableAttributedString(attributedString: bullet(color: dot))
        line.append(plain(name, color: TUIColors.text, bold: true))
        if !preview.isEmpty { line.append(plain("(\(preview))", color: TUIColors.text)) }
        line.addAttribute(.paragraphStyle, value: hangingStyle(firstCells: 0, restCells: Self.gutterCells),
                          range: NSRange(location: 0, length: line.length))
        return line
    }

    func subagent(label: String, state: String) -> NSAttributedString {
        let line = NSMutableAttributedString(attributedString: bullet(color: TUIColors.claude))
        line.append(plain(label, color: TUIColors.text, bold: true))
        line.append(plain(" · \(state)", color: TUIColors.dim))
        return line
    }

    // MARK: Primitives

    private func bullet(color: UIColor) -> NSAttributedString {
        plain(Self.bulletGlyph + " ", color: color)
    }

    func plain(_ text: String, color: UIColor, bold: Bool = false, italic: Bool = false) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: style.font(bold: bold, italic: italic),
            .foregroundColor: color,
        ])
    }

    private func inline(_ markdown: String, bold: Bool = false, italic: Bool = false,
                        underline: Bool = false, color: UIColor = TUIColors.text) -> NSAttributedString {
        let attributed = chatInlineAttributed(markdown)
        let result = NSMutableAttributedString()
        for run in attributed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let isCode = intent.contains(.code)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: style.font(bold: bold || intent.contains(.stronglyEmphasized),
                                  italic: italic || intent.contains(.emphasized)),
                .foregroundColor: isCode ? TUIColors.code : color,
            ]
            if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = TUIColors.code
            }
            result.append(NSAttributedString(string: String(attributed[run.range].characters), attributes: attributes))
        }
        return result
    }

    private func hangingStyle(firstCells: Int, restCells: Int) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = CGFloat(firstCells) * style.cellWidth
        paragraph.headIndent = CGFloat(restCells) * style.cellWidth
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }
}
