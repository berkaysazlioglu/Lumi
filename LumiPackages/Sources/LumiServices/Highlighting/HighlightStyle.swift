import AppKit
import Foundation

/// Vurgulayıcının görsel parametreleri (refactor 7.5, karar 111).
///
/// Motor LumiServices'te yaşadığı için `Theme`/`LumiFonts`'u GÖREMEZ (katman
/// kuralı): düz metin rengi ve font composition root'tan enjekte edilir.
/// Renkler highlight.js kapsam adına (`title.function`, `variable.language`)
/// göre çözülür; tam ad yoksa en uzun ön ek kullanılır (`title.function` →
/// `title`). Highlightr'ın CSS okuyucusu iki parçalı seçicileri
/// (`.hljs-title.class_`) okuyamadığı için tip/fonksiyon/sınıf adları renksiz
/// kalıyordu — tablo bunu kökten çözer.
public struct HighlightStyle: Sendable {
    public struct ScopeStyle: Sendable {
        public let color: NSColor?
        public let isItalic: Bool
        public let isBold: Bool

        public init(color: NSColor?, isItalic: Bool = false, isBold: Bool = false) {
            self.color = color
            self.isItalic = isItalic
            self.isBold = isBold
        }
    }

    /// Vurgulanamayan (düz metin) içeriğin rengi.
    public let plainTextColor: NSColor
    /// Punto → monospace font çözümü (regular).
    public let font: @Sendable (CGFloat) -> NSFont
    public let scopes: [String: ScopeStyle]

    public init(
        plainTextColor: NSColor = NSColor(hex: 0xABB2BF),
        font: @escaping @Sendable (CGFloat) -> NSFont = {
            .monospacedSystemFont(ofSize: $0, weight: .regular)
        },
        scopes: [String: ScopeStyle] = HighlightStyle.atomOneDark
    ) {
        self.plainTextColor = plainTextColor
        self.font = font
        self.scopes = scopes
    }

    /// Kapsamın stili: tam ad, yoksa sondan bileşen düşürerek en uzun ön ek.
    public func style(forScope scope: String) -> ScopeStyle? {
        var candidate = Substring(scope)
        while true {
            if let style = scopes[String(candidate)] { return style }
            guard let dot = candidate.lastIndex(of: ".") else { return nil }
            candidate = candidate[..<dot]
        }
    }

    /// atom-one-dark (highlight.js 11 CSS'iyle birebir) + CSS'in boş bıraktığı
    /// `property` ve `variable.language` için One Dark karşılıkları.
    public static let atomOneDark: [String: ScopeStyle] = {
        let grey = NSColor(hex: 0x5C6370)
        let purple = NSColor(hex: 0xC678DD)
        let red = NSColor(hex: 0xE06C75)
        let cyan = NSColor(hex: 0x56B6C2)
        let green = NSColor(hex: 0x98C379)
        let orange = NSColor(hex: 0xD19A66)
        let blue = NSColor(hex: 0x61AEEE)
        let yellow = NSColor(hex: 0xE6C07B)
        var table: [String: ScopeStyle] = [:]
        func set(_ color: NSColor?, italic: Bool = false, bold: Bool = false, _ names: String...) {
            for name in names { table[name] = ScopeStyle(color: color, isItalic: italic, isBold: bold) }
        }
        set(grey, italic: true, "comment", "quote")
        set(purple, "doctag", "keyword", "formula", "template-tag")
        set(red, "section", "name", "selector-tag", "deletion", "subst", "property", "variable.language")
        set(cyan, "literal", "operator.word")
        set(green, "string", "regexp", "addition", "attribute", "meta.string", "char.escape")
        set(orange, "attr", "variable", "template-variable", "type", "selector-class", "selector-attr",
            "selector-pseudo", "number", "variable.constant", "params.default")
        set(blue, "symbol", "bullet", "link", "meta", "selector-id", "title", "title.function")
        set(yellow, "built_in", "title.class", "title.class.inherited")
        set(nil, italic: true, "emphasis")
        set(nil, bold: true, "strong")
        return table
    }()
}

public extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
