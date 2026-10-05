import AppKit
import Foundation

/// highlight.js'in HTML çıktısı → `NSAttributedString` (karar 111).
///
/// hljs yalnız iç içe `<span class="…">` ve kaçışlı metin üretir; tam bir HTML
/// ayrıştırıcısı gerekmez. Sınıf listesi kapsam adına iner
/// (`hljs-title function_` → `title.function`, `language-xml` → kapsamsız),
/// stil `HighlightStyle`'dan çözülür. İç kapsam rengi ezer; italik/kalın
/// CSS'teki gibi devralınır.
enum HighlightHTMLRenderer {
    struct Run: Equatable {
        let text: String
        /// İçten dışa kapsam yığını (en içteki önce); kapsamsız metinde boş.
        let scopes: [String]
    }

    /// Saf ayrıştırma: metin parçaları + her parçanın kapsam yığını.
    static func runs(fromHTML html: String) -> [Run] {
        var runs: [Run] = []
        var stack: [String?] = []
        var text = ""
        var index = html.startIndex

        func flush() {
            guard !text.isEmpty else { return }
            runs.append(Run(text: text, scopes: stack.reversed().compactMap { $0 }))
            text = ""
        }

        while index < html.endIndex {
            let character = html[index]
            if character == "<" {
                guard let close = html[index...].firstIndex(of: ">") else { break }
                let tag = html[html.index(after: index)..<close]
                flush()
                if tag.hasPrefix("/") {
                    if !stack.isEmpty { stack.removeLast() }
                } else {
                    stack.append(scope(fromTag: tag))
                }
                index = html.index(after: close)
            } else if character == "&", let semicolon = html[index...].prefix(10).firstIndex(of: ";") {
                let entity = html[html.index(after: index)..<semicolon]
                if let decoded = decode(entity) {
                    text.append(decoded)
                    index = html.index(after: semicolon)
                } else {
                    text.append(character)
                    index = html.index(after: index)
                }
            } else {
                text.append(character)
                index = html.index(after: index)
            }
        }
        flush()
        return runs
    }

    static func attributed(fromHTML html: String, style: HighlightStyle, fontSize: CGFloat) -> NSAttributedString {
        let fonts = FontSet(base: style.font(fontSize))
        let result = NSMutableAttributedString()
        result.beginEditing()
        for run in runs(fromHTML: html) {
            var color: NSColor?
            var isItalic = false
            var isBold = false
            for scope in run.scopes {
                guard let scopeStyle = style.style(forScope: scope) else { continue }
                if color == nil { color = scopeStyle.color }
                isItalic = isItalic || scopeStyle.isItalic
                isBold = isBold || scopeStyle.isBold
            }
            result.append(NSAttributedString(string: run.text, attributes: [
                .font: fonts.font(italic: isItalic, bold: isBold),
                .foregroundColor: color ?? style.plainTextColor,
            ]))
        }
        result.endEditing()
        return result
    }

    /// `span class="hljs-title function_"` → `title.function`; hljs dışı sınıf → nil.
    static func scope(fromTag tag: Substring) -> String? {
        guard let start = tag.range(of: "class=\"") else { return nil }
        let classes = tag[start.upperBound...].prefix { $0 != "\"" }.split(separator: " ")
        guard let first = classes.first, first.hasPrefix("hljs-") else { return nil }
        let modifiers = classes.dropFirst().map(\.trimmingTrailingUnderscores)
        return ([String(first.dropFirst("hljs-".count))] + modifiers).joined(separator: ".")
    }

    private static func decode(_ entity: Substring) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            guard entity.hasPrefix("#") else { return nil }
            let digits = entity.dropFirst()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
    }

    /// Dört font kesiti çağrı başına bir kez türetilir.
    private struct FontSet {
        let regular: NSFont
        let italic: NSFont
        let bold: NSFont
        let boldItalic: NSFont

        init(base: NSFont) {
            let manager = NSFontManager.shared
            regular = base
            italic = manager.convert(base, toHaveTrait: .italicFontMask)
            bold = manager.convert(base, toHaveTrait: .boldFontMask)
            boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)
        }

        func font(italic isItalic: Bool, bold isBold: Bool) -> NSFont {
            switch (isItalic, isBold) {
            case (false, false): regular
            case (true, false): italic
            case (false, true): bold
            case (true, true): boldItalic
            }
        }
    }
}

private extension Substring {
    var trimmingTrailingUnderscores: String {
        var value = self
        while value.hasSuffix("_") { value = value.dropLast() }
        return String(value)
    }
}
