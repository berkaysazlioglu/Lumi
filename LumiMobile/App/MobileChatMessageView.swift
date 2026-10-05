// LumiMobile/App/MobileChatMessageView.swift
import SwiftUI
import UIKit
import LumiMobileKit
import LumiWire

/// A folded turn: the owner message's text bubble + tool activity folded beneath it.
struct MobileChatMessageView: View {
    let turn: FoldedTurn

    @State private var copied = false

    var body: some View {
        VStack(alignment: turn.message.role == .user ? .trailing : .leading, spacing: 4) {
            if turn.message.role == .assistant, let text = chatCopyText(turn) {
                HStack {
                    Spacer()
                    Button {
                        performCopy(text)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy message")
                }
            }
            ForEach(Array(turn.message.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
            MobileChatToolRunView(activity: turn.toolActivity)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: turn.message.role == .user ? .trailing : .leading)
    }

    private func performCopy(_ text: String) {
        UIPasteboard.general.string = text
        copied = true
        // Revert the confirmation checkmark after a short beat (orca 700ms).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { copied = false }
    }

    @ViewBuilder
    private func blockView(_ block: ChatBlock) -> some View {
        switch block {
        case let .text(text, _):
            if turn.message.role == .user {
                Text(LocalizedStringKey(text))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: 300, alignment: .trailing)
            } else {
                // Assistant: plain prose without a bubble (orca style; spec 2026-09-17),
                // inline code / fenced blocks tinted like the Claude TUI.
                ChatMarkdownView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .toolCall(name, preview, _):
            Text("▶ \(name) \(preview)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .toolResult(output, isError):
            Text(output)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isError ? .red : .secondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

}
