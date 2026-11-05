import AppKit
import LumiKit
import SwiftUI

/// Uzak Claude chat'inin tipografisi: Mac'in terminal fontu, Claude Code TUI renkleri.
struct RemoteChatStyle {
    let family: String

    var size: CGFloat { Theme.Typography.Size.base.scaledPoints }

    func font(bold: Bool = false) -> Font {
        Font(LumiFonts.mono(family: family, size: size, weight: bold ? .bold : .regular))
    }

    /// `● ` / `> ` oluğu — tek aralıklı fontta iki hücre.
    static let bullet = "● "
    static let prompt = "> "
    static let toolOutput = "  ⎿  "
    /// Araç çıktısının `… +N lines`'tan önce gösterilen satırları (TUI varsayılanı).
    static let toolPreviewLines = 3
    static let ruleCells = 24
}

/// Katlanmış bir turn, Claude Code TUI'sinin çizdiği gibi: bantlı `> prompt`,
/// `● metin`, `● Araç(arg)` + `⎿ çıktı` (telefonun `MobileChatMessageView`'ının Mac karşılığı).
struct RemoteChatTurnView: View {
    let turn: FoldedTurn
    let style: RemoteChatStyle

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(tuiItems(for: turn).enumerated()), id: \.offset) { _, item in
                itemView(item)
            }
            if turn.message.role == .assistant, let text = chatCopyText(turn) {
                copyButton(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func itemView(_ item: TUIItem) -> some View {
        switch item {
        case let .user(text):
            gutter(RemoteChatStyle.prompt, color: Theme.textSecondary) {
                Text(text).font(style.font()).foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        case let .assistant(markdown):
            RemoteChatMarkdown(markdown: markdown, style: style)
        case let .tool(name, preview, result):
            RemoteChatToolView(name: name, preview: preview, result: result, style: style)
        case let .subagent(label, state):
            gutter(RemoteChatStyle.bullet, color: Theme.warning) {
                Text(label).font(style.font(bold: true)).foregroundStyle(Theme.textPrimary)
                    + Text(" · \(state)").font(style.font()).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func gutter<Content: View>(_ mark: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(mark).font(style.font()).foregroundStyle(color)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyButton(_ text: String) -> some View {
        IconButton(systemName: copied ? "checkmark" : "doc.on.doc", label: "Copy message") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: Self.copiedFeedback)
                copied = false
            }
        }
    }

    private static let copiedFeedback: Duration = .milliseconds(700)
}

/// Asistan markdown'ı TUI bloklarıyla: ilk blok `●` oluğunu taşır, diğerleri hizalanır.
struct RemoteChatMarkdown: View {
    let markdown: String
    let style: RemoteChatStyle

    var body: some View {
        let blocks = tuiMarkdownBlocks(markdown)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if blocks.isEmpty {
                Text(RemoteChatStyle.bullet).font(style.font()).foregroundStyle(Theme.textPrimary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(RemoteChatStyle.bullet)
                        .font(style.font())
                        .foregroundStyle(Theme.textPrimary)
                        .opacity(index == 0 ? 1 : 0)
                        .accessibilityHidden(index != 0)
                    blockView(block)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: TUIMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text, bold: true))
                .italic(level == 1)
                .underline(level == 1)
        case let .paragraph(text):
            Text(inline(text))
        case let .listItem(depth, marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(String(repeating: "  ", count: depth) + marker + " ")
                    .font(style.font())
                    .foregroundStyle(Theme.textPrimary)
                Text(inline(text))
            }
        case let .quote(text):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("▎ ").font(style.font()).foregroundStyle(Theme.textSecondary)
                Text(inline(text)).italic().foregroundStyle(Theme.textSecondary)
            }
        case let .code(_, body):
            wide(body)
        case let .table(header, rows):
            wide(tuiTableLines(header: header, rows: rows).joined(separator: "\n"))
        case .rule:
            Text(String(repeating: "─", count: RemoteChatStyle.ruleCells))
                .font(style.font())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Kod ve tablolar kırılmaz: geniş terminal satırı gibi yatay kayar.
    private func wide(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(style.font())
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(Theme.Spacing.md)
        }
        .background(Theme.bgSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    /// Satır içi markdown: kalın/italik font özelliği, `kod` ve linkler Claude'un izin mavisinde.
    private func inline(_ markdown: String, bold: Bool = false) -> AttributedString {
        var attributed = chatInlineAttributed(markdown)
        for run in attributed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = style.font(bold: bold || intent.contains(.stronglyEmphasized))
            if intent.contains(.emphasized) { font = font.italic() }
            attributed[run.range].font = font
            let isAccent = intent.contains(.code) || run.link != nil
            attributed[run.range].foregroundColor = isAccent ? Theme.accentPrimary : Theme.textPrimary
            if intent.contains(.strikethrough) { attributed[run.range].strikethroughStyle = .single }
        }
        return attributed
    }
}

/// `● Araç(arg)` + katlı `⎿` çıktısı; uzun çıktıya tıklayınca açılır.
private struct RemoteChatToolView: View {
    let name: String
    let preview: String
    let result: TUIToolResult?
    let style: RemoteChatStyle

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if !name.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(RemoteChatStyle.bullet).font(style.font()).foregroundStyle(dotColor)
                    (Text(name).font(style.font(bold: true))
                        + Text(preview.isEmpty ? "" : "(\(preview))").font(style.font()))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let result { output(result) }
        }
    }

    /// Sonuç gelince yeşil/kırmızı, koşarken sönük.
    private var dotColor: Color {
        guard let result else { return Theme.textSecondary }
        return result.isError ? Theme.error : Theme.success
    }

    private func output(_ result: TUIToolResult) -> some View {
        let limit = isExpanded ? Int.max : RemoteChatStyle.toolPreviewLines
        let folded = TUIFoldedOutput(result.output, limit: limit)
        let canToggle = folded.hiddenLineCount > 0 || isExpanded
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(RemoteChatStyle.toolOutput).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(folded.visible.isEmpty ? "(No output)" : folded.visible)
                    .foregroundStyle(result.isError ? Theme.error : Theme.textSecondary)
                if folded.hiddenLineCount > 0 {
                    Text("… +\(folded.hiddenLineCount) lines ").foregroundStyle(Theme.textSecondary)
                        + Text("(click to expand)").italic().foregroundStyle(Theme.textMuted)
                }
            }
        }
        .font(style.font())
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canToggle else { return }
            withAnimation(Theme.Motion.standardEase) { isExpanded.toggle() }
        }
        .contextMenu {
            Button("Copy Output") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.output, forType: .string)
            }
        }
    }
}
