// LumiMobile/App/ChatMarkdownView.swift
import SwiftUI
import LumiMobileKit

/// Assistant prose with Claude-TUI-style tinting: inline `code` (class names,
/// paths) in the accent color on a subtle background; fenced blocks in a
/// horizontally scrolling monospace card.
struct ChatMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chatMarkdownSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .prose(prose):
                    Text(tinted(prose))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .code(language, body):
                    codeBlock(language: language, body: body)
                }
            }
        }
    }

    private func tinted(_ prose: String) -> AttributedString {
        var attr = chatInlineAttributed(prose)
        for run in attr.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attr[run.range].foregroundColor = Color.accentColor
            attr[run.range].backgroundColor = Color.accentColor.opacity(0.12)
            attr[run.range].font = .system(.callout, design: .monospaced)
        }
        return attr
    }

    private func codeBlock(language: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language {
                Text(language).font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(body)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
