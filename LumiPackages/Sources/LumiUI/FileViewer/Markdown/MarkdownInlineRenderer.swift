import Foundation
import LumiKit
import SwiftUI

/// Karar 109: satır-içi markdown modeli → tema'lı `AttributedString`.
///
/// İç içe biçim (`***kalın italik***`, link içinde kod) bir stil yığınıyla
/// çözülür: her düğüm üst düğümün stilini devralır, kendi özelliğini ekler.
/// Link'ler `.link` attribute'u taşır; tıklama `MarkdownDocumentView`'ın
/// `openURL` eylemine düşer.
enum MarkdownInlineRenderer {
    struct Style {
        var size: Theme.Typography.Size
        var weight: Font.Weight = .regular
        var isItalic = false
        var isStrikethrough = false
        var link: URL?
        var color: Color = Theme.textPrimary
    }

    static func attributed(_ inlines: [MarkdownInline], style: Style) -> AttributedString {
        inlines.reduce(into: AttributedString()) { result, inline in
            result.append(attributed(inline, style: style))
        }
    }

    private static func attributed(_ inline: MarkdownInline, style: Style) -> AttributedString {
        switch inline {
        case .text(let text):
            return run(text, style: style)
        case .softBreak:
            return run(" ", style: style)
        case .lineBreak:
            return run("\n", style: style)
        case .html(let html):
            return run(html, style: style, font: Theme.Typography.mono(style.size.stepped(-1)), color: Theme.textSecondary)
        case .code(let code):
            var piece = run(code, style: style, font: Theme.Typography.mono(style.size.stepped(-1)), color: Theme.accentCyan)
            piece.backgroundColor = Theme.bgElevated
            return piece
        case .emphasis(let children):
            var nested = style
            nested.isItalic = true
            return attributed(children, style: nested)
        case .strong(let children):
            var nested = style
            nested.weight = .bold
            return attributed(children, style: nested)
        case .strikethrough(let children):
            var nested = style
            nested.isStrikethrough = true
            return attributed(children, style: nested)
        case .link(let destination, let content):
            var nested = style
            nested.link = destination.flatMap(linkURL)
            nested.color = Theme.accentPrimary
            return attributed(content, style: nested)
        case .image(_, let alt):
            // Görsel yüklenmez (karar 109 kapsam dışı): alt metni işaretli kalır.
            var nested = style
            nested.isItalic = true
            nested.color = Theme.textSecondary
            return run("[\(alt.isEmpty ? "image" : alt)]", style: nested)
        }
    }

    private static func run(
        _ text: String,
        style: Style,
        font: Font? = nil,
        color: Color? = nil
    ) -> AttributedString {
        var piece = AttributedString(text)
        var resolved = font ?? Theme.Typography.ui(style.size, weight: style.weight)
        if style.isItalic { resolved = resolved.italic() }
        piece.font = resolved
        piece.foregroundColor = color ?? style.color
        if style.isStrikethrough { piece.strikethroughStyle = .single }
        if let link = style.link {
            piece.link = link
            piece.underlineStyle = .single
        }
        return piece
    }

    /// `#anchor`, göreli yol ve mutlak URL hepsi `URL(string:)` ile taşınır;
    /// yorumlamayı `MarkdownLinkTarget` yapar. Boşluklu yol kaçışlanır.
    private static func linkURL(_ destination: String) -> URL? {
        URL(string: destination)
            ?? destination.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }
}
