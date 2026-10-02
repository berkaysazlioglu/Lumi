// LumiMobile/App/ChatMarkdownView.swift
import SwiftUI
import UIKit
import LumiMobileKit

/// Assistant prose with Claude-TUI-style tinting: inline `code` (class names,
/// paths) in the accent color on a subtle background; fenced blocks in a
/// horizontally scrolling monospace card. Both use `SelectableText` so any
/// range can be selected and copied (SwiftUI `Text` only copies it whole).
struct ChatMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chatMarkdownSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .prose(prose):
                    SelectableText(text: Self.tinted(prose))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .code(language, body):
                    codeBlock(language: language, body: body)
                }
            }
        }
    }

    /// Inline markdown → UIKit attributes: body text in the label color, inline
    /// code in a monospaced accent font on a faint accent background,
    /// bold/italic as font traits, links as `.link`.
    static func tinted(_ prose: String) -> NSAttributedString {
        let attr = chatInlineAttributed(prose)
        let body = UIFont.preferredFont(forTextStyle: .body)
        let callout = UIFont.preferredFont(forTextStyle: .callout)
        let result = NSMutableAttributedString()
        for run in attr.runs {
            let piece = String(attr[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label]
            if intent.contains(.code) {
                attributes[.font] = UIFont.monospacedSystemFont(ofSize: callout.pointSize, weight: .regular)
                attributes[.foregroundColor] = UIColor.tintColor
                attributes[.backgroundColor] = UIColor.tintColor.withAlphaComponent(0.12)
            } else {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                let descriptor = body.fontDescriptor.withSymbolicTraits(traits) ?? body.fontDescriptor
                attributes[.font] = UIFont(descriptor: descriptor, size: body.pointSize)
            }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
    }

    private static func codeText(_ body: String) -> NSAttributedString {
        let footnote = UIFont.preferredFont(forTextStyle: .footnote)
        return NSAttributedString(string: body, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: footnote.pointSize, weight: .regular),
            .foregroundColor: UIColor.label,
        ])
    }

    private func codeBlock(language: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language {
                Text(language).font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                SelectableText(text: Self.codeText(body), wraps: false)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
