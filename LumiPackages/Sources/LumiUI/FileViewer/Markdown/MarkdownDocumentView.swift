import LumiKit
import SwiftUI

/// Karar 109: FileViewer view modunda markdown dökümanının GitHub düzeninde
/// render'ı — cmark-gfm ağacı (`MarkdownDocument`) native SwiftUI bloklarıyla
/// çizilir: başlık merdiveni (H1/H2 alt çizgili), birleşik paragraflar, iç içe
/// ve görev listeleri, alıntı, vurgulu kod blokları, ızgara tablolar.
///
/// Diff modu bilinçli olarak satır tabanlı `MarkdownDiffView`'da kalır:
/// ekleme/silme işaretleri kaynak satırına bağlıdır, blok ağacı satır tutmaz.
struct MarkdownDocumentView: View {
    let document: MarkdownDocument
    let highlighter: any SyntaxHighlighting
    /// Tıklanan link (`MarkdownLinkTarget` çözer).
    let onOpenLink: (URL) -> Void

    /// Okunabilir satır uzunluğu: geniş modalda metin kenardan kenara akmaz
    /// (GitHub'ın makale genişliği paritesi).
    private static var readableWidth: CGFloat { Theme.scaled(980) }

    var body: some View {
        ScrollView(.vertical) {
            MarkdownBlocksView(
                blocks: document.blocks,
                context: MarkdownRenderContext(highlighter: highlighter)
            )
            .frame(maxWidth: Self.readableWidth, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xxxl)
            .padding(.vertical, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.bgSurface)
        .environment(\.openURL, OpenURLAction { url in
            onOpenLink(url)
            return .handled
        })
    }
}

/// Bloklar arası aktarılan render durumu (iç içe liste derinliği, alıntı
/// içinde ikincil metin rengi).
struct MarkdownRenderContext {
    let highlighter: any SyntaxHighlighting
    var size: Theme.Typography.Size = .base
    var textColor: Color = Theme.textPrimary
    var listDepth = 0

    func inlineStyle(size: Theme.Typography.Size? = nil, weight: Font.Weight = .regular) -> MarkdownInlineRenderer.Style {
        MarkdownInlineRenderer.Style(size: size ?? self.size, weight: weight, color: textColor)
    }
}

/// Blok dizisi; liste maddesi ve alıntı içinde özyinelemeli kullanılır.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let context: MarkdownRenderContext
    var spacing: CGFloat = Theme.Spacing.lg

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, context: context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let context: MarkdownRenderContext

    var body: some View {
        switch block {
        case .heading(let level, let content):
            heading(level: level, content: content)
        case .paragraph(let inlines):
            prose(inlines)
        case .blockQuote(let children):
            quote(children)
        case .list(let list):
            MarkdownListView(list: list, context: context)
        case .codeBlock(let language, let code):
            MarkdownCodeBlockView(language: language, code: code, highlighter: context.highlighter, size: context.size)
        case .table(let table):
            MarkdownTableView(table: table, context: context)
        case .thematicBreak:
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.scaled(2))
                .padding(.vertical, Theme.Spacing.sm)
        case .html(let html):
            Text(html)
                .font(Theme.Typography.mono(context.size.stepped(-1)))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func prose(_ inlines: [MarkdownInline]) -> some View {
        Text(MarkdownInlineRenderer.attributed(inlines, style: context.inlineStyle()))
            .lineSpacing(Theme.Spacing.xs)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func heading(level: Int, content: [MarkdownInline]) -> some View {
        let size = MarkdownRowFormatting.headingSize(level, base: context.size)
        var style = context.inlineStyle(size: size, weight: level <= 2 ? .bold : .semibold)
        if level <= 2 { style.color = Theme.accentPrimary }
        if level >= 6 { style.color = Theme.textSecondary }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(MarkdownInlineRenderer.attributed(content, style: style))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if level <= 2 {
                Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            }
        }
        .padding(.top, level <= 2 ? Theme.Spacing.md : Theme.Spacing.xs)
        .accessibilityAddTraits(.isHeader)
    }

    private func quote(_ children: [MarkdownBlock]) -> some View {
        var nested = context
        nested.textColor = Theme.textSecondary
        return HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            Rectangle()
                .fill(Theme.accentPrimary.opacity(0.5))
                .frame(width: Theme.scaled(3))
            MarkdownBlocksView(blocks: children, context: nested, spacing: Theme.Spacing.md)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Liste

private struct MarkdownListView: View {
    let list: MarkdownList
    let context: MarkdownRenderContext

    private static var markerWidth: CGFloat { Theme.scaled(22) }

    var body: some View {
        var nested = context
        nested.listDepth += 1
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    marker(for: item, index: index)
                        .frame(width: Self.markerWidth, alignment: .trailing)
                    MarkdownBlocksView(blocks: item.blocks, context: nested, spacing: Theme.Spacing.xs)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, index: Int) -> some View {
        if let isChecked = item.checkbox {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(Theme.Typography.ui(context.size))
                .foregroundStyle(isChecked ? Theme.accentPrimary : Theme.textSecondary)
                .accessibilityLabel(isChecked ? "Completed" : "Not completed")
        } else if let start = list.startIndex {
            Text("\(start + index).")
                .font(Theme.Typography.ui(context.size))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        } else {
            Text(MarkdownListMarker.bullet(depth: context.listDepth))
                .font(Theme.Typography.ui(context.size, weight: .bold))
                .foregroundStyle(Theme.accentCyan)
        }
    }
}

/// GitHub paritesi: derinlik arttıkça dolu → boş → kare madde işareti.
enum MarkdownListMarker {
    static func bullet(depth: Int) -> String {
        switch depth % 3 {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }
}

// MARK: - Kod bloğu

/// Fence diliyle vurgulanır (`SyntaxHighlighting`, async); dil bilinmiyorsa
/// düz monospace. Uzun satır sarılmaz, blok yatay kayar (GitHub paritesi).
private struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String
    let highlighter: any SyntaxHighlighting
    let size: Theme.Typography.Size

    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView(.horizontal) {
            Group {
                if let highlighted {
                    Text(highlighted)
                } else {
                    Text(code)
                        .font(Theme.Typography.mono(size.stepped(-1)))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .lineSpacing(Theme.Spacing.xxs)
            .fixedSize(horizontal: true, vertical: true)
            .textSelection(.enabled)
            .padding(Theme.Spacing.lg)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(alignment: .topTrailing) {
            if let language {
                Text(language.lowercased())
                    .font(Theme.Typography.mono(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .padding(Theme.Spacing.sm)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.border, lineWidth: Theme.Stroke.hairline)
                .allowsHitTesting(false)
        )
        .task(id: code) {
            guard let fileName = MarkdownCodeLanguage.fileName(for: language) else { return }
            let result = await highlighter.highlight(
                code: code,
                fileName: fileName,
                fontSize: size.stepped(-1).scaledPoints
            )
            // Vurgulayıcı boş dönerse (dil tanınmadı) düz metin kalır.
            guard result.length > 0 else { return }
            highlighted = try? AttributedString(result, including: \.appKit)
        }
    }
}

// MARK: - Tablo

/// GFM tablosu: başlık satırı kalın + yükseltilmiş zemin, satırlar zebra,
/// hücreler ızgara çizgili ve sütun hizalı. Sütun genişliği içeriğe göre
/// paylaştırılır (`MarkdownTableLayout`); tablo kabı zorla doldurmaz.
private struct MarkdownTableView: View {
    let table: MarkdownTable
    let context: MarkdownRenderContext

    var body: some View {
        MarkdownTableLayout(columnCount: table.columnCount) {
            ForEach(0..<table.columnCount, id: \.self) { column in
                cell(table.header[column], column: column, weight: .semibold, background: Theme.bgElevated)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                ForEach(0..<table.columnCount, id: \.self) { column in
                    cell(
                        row[column],
                        column: column,
                        weight: .regular,
                        background: index.isMultiple(of: 2) ? Theme.bgSurface : Theme.bgDeep.opacity(0.5)
                    )
                }
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Theme.border, lineWidth: Theme.Stroke.hairline)
                .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(
        _ inlines: [MarkdownInline],
        column: Int,
        weight: Font.Weight,
        background: Color
    ) -> some View {
        let alignment = Self.alignment(table.alignments[column])
        return Text(MarkdownInlineRenderer.attributed(inlines, style: context.inlineStyle(weight: weight)))
            .multilineTextAlignment(Self.textAlignment(table.alignments[column]))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(background)
            .overlay(
                Rectangle()
                    .strokeBorder(Theme.border, lineWidth: Theme.Stroke.hairline)
                    .allowsHitTesting(false)
            )
    }

    private static func alignment(_ alignment: MarkdownTable.Alignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private static func textAlignment(_ alignment: MarkdownTable.Alignment) -> TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

#if DEBUG
#Preview("MarkdownDocumentView") {
    MarkdownDocumentView(
        document: MarkdownDocument(blocks: [
            .heading(level: 1, content: [.text("ContainerSystem — findings report")]),
            .paragraph([.text("A project-agnostic reading of "), .strong([.text("findings")]), .text(" C1–C3.")]),
            .heading(level: 2, content: [.text("Summary")]),
            .table(MarkdownTable(
                alignments: [.leading, .leading, .center],
                header: [[.text("#")], [.text("Finding")], [.text("Value")]],
                rows: [
                    [[.text("C1")], [.text("No constructor or type injection")], [.text("High")]],
                    [[.text("C2")], [.text("No "), .code("collection"), .text(" injection")], [.text("High")]],
                ]
            )),
            .list(MarkdownList(startIndex: nil, items: [
                MarkdownListItem(checkbox: true, blocks: [.paragraph([.text("done")])]),
                MarkdownListItem(checkbox: false, blocks: [.paragraph([.text("open")])]),
            ])),
            .codeBlock(language: "swift", code: "let container = Container()"),
        ]),
        highlighter: ShellContext.preview().highlighter,
        onOpenLink: { _ in }
    )
    .frame(width: 760, height: 560)
}
#endif
