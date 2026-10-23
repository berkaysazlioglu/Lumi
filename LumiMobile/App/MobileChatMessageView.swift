// LumiMobile/App/MobileChatMessageView.swift
import SwiftUI
import UIKit
import LumiMobileKit
import LumiWire

/// A folded turn drawn the way the Claude Code TUI draws it: `> prompt` on a
/// band, `⏺ prose`, `⏺ Tool(arg)` + `⎿ output` — all in the terminal font.
struct MobileChatMessageView: View {
    let turn: FoldedTurn

    @Environment(\.tuiStyle) private var style
    @State private var copied = false

    /// Lines of tool output shown before `… +N lines` (TUI default).
    static let toolOutputPreviewLines = 3

    var body: some View {
        let renderer = TUIRenderer(style: style)
        VStack(alignment: .leading, spacing: style.font().lineHeight * 0.4) {
            ForEach(Array(tuiItems(for: turn).enumerated()), id: \.offset) { _, item in
                itemView(item, renderer: renderer)
            }
            if turn.message.role == .assistant, let text = chatCopyText(turn) {
                copyButton(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func itemView(_ item: TUIItem, renderer: TUIRenderer) -> some View {
        switch item {
        case let .user(text):
            SelectableText(text: renderer.user(text))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(TUIColors.userBand), in: RoundedRectangle(cornerRadius: 4))
        case let .assistant(markdown):
            ForEach(Array(renderer.assistant(markdown).enumerated()), id: \.offset) { _, piece in
                pieceView(piece)
            }
        case let .tool(name, preview, result):
            TUIToolView(name: name, preview: preview, result: result, renderer: renderer)
        case let .subagent(label, state):
            SelectableText(text: renderer.subagent(label: label, state: state))
        }
    }

    @ViewBuilder
    private func pieceView(_ piece: TUIPiece) -> some View {
        switch piece {
        case let .text(text):
            SelectableText(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .wide(text, indentCells):
            ScrollView(.horizontal, showsIndicators: false) {
                SelectableText(text: text, wraps: false)
                    .padding(8)
            }
            .background(Color(TUIColors.codeBand), in: RoundedRectangle(cornerRadius: 4))
            .padding(.leading, CGFloat(indentCells) * style.cellWidth)
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            // Revert the confirmation checkmark after a short beat (orca 700ms).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(Color(TUIColors.dim))
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(TUIRenderer.gutterCells) * style.cellWidth)
        .accessibilityLabel("Copy message")
    }
}

/// `⏺ Tool(arg)` + folded `⎿` output; tapping a long output expands it.
private struct TUIToolView: View {
    let name: String
    let preview: String
    let result: TUIToolResult?
    let renderer: TUIRenderer

    @Environment(\.tuiStyle) private var style
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !name.isEmpty {
                SelectableText(text: renderer.toolCall(name: name, preview: preview, result: result))
            }
            if let result { output(result) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// SwiftUI text (not the selectable UITextView) so the tap reliably toggles;
    /// copying goes through the context menu.
    private func output(_ result: TUIToolResult) -> some View {
        let limit = expanded ? Int.max : MobileChatMessageView.toolOutputPreviewLines
        let folded = TUIFoldedOutput(result.output, limit: limit)
        let font = Font(style.font())
        let dim = Color(TUIColors.dim)
        return Button {
            guard folded.hiddenLineCount > 0 || expanded else { return }
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("  ⎿  ").foregroundStyle(dim)
                VStack(alignment: .leading, spacing: 0) {
                    Text(folded.visible.isEmpty ? "(No output)" : folded.visible)
                        .foregroundStyle(result.isError ? Color(TUIColors.error) : dim)
                    if folded.hiddenLineCount > 0 {
                        Text("… +\(folded.hiddenLineCount) lines ").foregroundStyle(dim)
                            + Text("(tap to expand)").italic().foregroundStyle(dim)
                    }
                }
                .multilineTextAlignment(.leading)
            }
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { UIPasteboard.general.string = result.output } label: {
                Label("Copy output", systemImage: "doc.on.doc")
            }
        }
    }
}
