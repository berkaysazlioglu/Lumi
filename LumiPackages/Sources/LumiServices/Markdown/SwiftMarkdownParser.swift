import Foundation
import LumiKit
import Markdown

/// `MarkdownParsing`'in tek implementasyonu (karar 109): swift-markdown
/// (cmark-gfm) ağacı → LumiKit'in saf `MarkdownDocument` modeli. Paket
/// tipleri bu dosyanın dışına çıkmaz.
///
/// Modelin tanımadığı düğümler (Doxygen/directive gibi DocC uzantıları)
/// kaybolmaz: kaynak hâliyle (`format()`) düz paragraf olarak iner.
public struct SwiftMarkdownParser: MarkdownParsing {
    public init() {}

    public func parse(_ text: String) -> MarkdownDocument {
        let document = Document(parsing: text)
        var blocks: [MarkdownBlock] = []
        var lines: [Int] = []
        for child in document.children {
            guard let block = Self.block(child) else { continue }
            blocks.append(block)
            lines.append(child.range?.lowerBound.line ?? lines.last ?? 1)
        }
        return MarkdownDocument(blocks: blocks, blockStartLines: lines)
    }

    // MARK: - Bloklar

    private static func blocks(_ children: MarkupChildren) -> [MarkdownBlock] {
        children.compactMap(block)
    }

    private static func block(_ markup: Markup) -> MarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, content: inlines(heading.children))
        case let paragraph as Paragraph:
            return .paragraph(inlines(paragraph.children))
        case let quote as BlockQuote:
            return .blockQuote(blocks(quote.children))
        case let list as OrderedList:
            return .list(MarkdownList(startIndex: Int(list.startIndex), items: items(list.listItems)))
        case let list as UnorderedList:
            return .list(MarkdownList(startIndex: nil, items: items(list.listItems)))
        case let code as CodeBlock:
            return .codeBlock(language: language(code.language), code: trimmingFinalNewline(code.code))
        case let table as Table:
            return .table(self.table(table))
        case is ThematicBreak:
            return .thematicBreak
        case let html as HTMLBlock:
            return .html(trimmingFinalNewline(html.rawHTML))
        default:
            let source = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            return source.isEmpty ? nil : .paragraph([.text(source)])
        }
    }

    private static func items(_ listItems: some Sequence<ListItem>) -> [MarkdownListItem] {
        listItems.map { item in
            let checkbox: Bool? = switch item.checkbox {
            case .checked: true
            case .unchecked: false
            case nil: nil
            }
            return MarkdownListItem(checkbox: checkbox, blocks: blocks(item.children))
        }
    }

    private static func table(_ table: Table) -> MarkdownTable {
        let header: [[MarkdownInline]] = Array(table.head.cells.map { inlines($0.children) })
        let rows: [[[MarkdownInline]]] = table.body.rows.map { row in
            Array(row.cells.map { inlines($0.children) })
        }
        let columnCount = max(table.columnAlignments.count, header.count, rows.map(\.count).max() ?? 0)
        let alignments = (0..<columnCount).map { index -> MarkdownTable.Alignment in
            guard index < table.columnAlignments.count else { return .leading }
            switch table.columnAlignments[index] {
            case .center: return .center
            case .right: return .trailing
            case .left, nil: return .leading
            }
        }
        return MarkdownTable(
            alignments: alignments,
            header: padded(header, to: columnCount),
            rows: rows.map { padded($0, to: columnCount) }
        )
    }

    private static func padded(_ cells: [[MarkdownInline]], to count: Int) -> [[MarkdownInline]] {
        cells.count >= count ? Array(cells.prefix(count)) : cells + Array(repeating: [], count: count - cells.count)
    }

    /// Bilgi dizisinin ilk sözcüğü (` ```swift title="x" ` → `swift`).
    private static func language(_ info: String?) -> String? {
        guard let word = info?.split(separator: " ").first, !word.isEmpty else { return nil }
        return String(word)
    }

    private static func trimmingFinalNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    // MARK: - Satır-içi

    private static func inlines(_ children: MarkupChildren) -> [MarkdownInline] {
        children.compactMap(inline)
    }

    private static func inline(_ markup: Markup) -> MarkdownInline? {
        switch markup {
        case let text as Text: return .text(text.string)
        case let emphasis as Emphasis: return .emphasis(inlines(emphasis.children))
        case let strong as Strong: return .strong(inlines(strong.children))
        case let strike as Strikethrough: return .strikethrough(inlines(strike.children))
        case let code as InlineCode: return .code(code.code)
        case let link as Link: return .link(destination: link.destination, content: inlines(link.children))
        case let image as Image: return .image(source: image.source, alt: image.plainText)
        case is SoftBreak: return .softBreak
        case is LineBreak: return .lineBreak
        case let html as InlineHTML: return .html(html.rawHTML)
        case let symbol as SymbolLink: return .code(symbol.destination ?? "")
        default:
            // InlineAttributes vb.: içerik düz metin olarak korunur, işaret düşer.
            let text = inlines(markup.children).plainText
            return text.isEmpty ? nil : .text(text)
        }
    }
}
