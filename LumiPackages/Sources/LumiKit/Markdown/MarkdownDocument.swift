import Foundation

/// Karar 109: render'lı markdown dökümanının SAF ağacı. Ayrıştırma
/// (`MarkdownParsing`, cmark-gfm) LumiServices'tedir; LumiUI yalnız bu modeli
/// çizer — parser paketi view modülüne sızmaz (karar 33 / Highlightr kalıbı).
///
/// Kapsam GitHub Flavored Markdown'dır: başlık, paragraf, alıntı, sıralı /
/// sırasız / görev listesi (iç içe), fence'li ve girintili kod, tablo (sütun
/// hizasıyla), yatay ayraç, ham HTML bloğu; satır-içi vurgu, kalın,
/// üstü-çizili, kod, link, görsel, yumuşak/sert satır sonu.
public struct MarkdownDocument: Sendable, Equatable {
    public let blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

public indirect enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, content: [MarkdownInline])
    case paragraph([MarkdownInline])
    case blockQuote([MarkdownBlock])
    case list(MarkdownList)
    /// `language` fence'in bilgi dizisinin ilk sözcüğüdür; girintili kodda nil.
    case codeBlock(language: String?, code: String)
    case table(MarkdownTable)
    case thematicBreak
    /// Ham HTML bloğu — yorumlanmaz, kaynak hâliyle gösterilir.
    case html(String)
}

public struct MarkdownList: Sendable, Equatable {
    /// Sıralı listede ilk numara; sırasız listede nil.
    public let startIndex: Int?
    public let items: [MarkdownListItem]

    public init(startIndex: Int?, items: [MarkdownListItem]) {
        self.startIndex = startIndex
        self.items = items
    }

    public var isOrdered: Bool { startIndex != nil }
}

public struct MarkdownListItem: Sendable, Equatable {
    /// Görev listesi kutusu (`- [ ]` / `- [x]`); düz maddede nil.
    public let checkbox: Bool?
    public let blocks: [MarkdownBlock]

    public init(checkbox: Bool?, blocks: [MarkdownBlock]) {
        self.checkbox = checkbox
        self.blocks = blocks
    }
}

public struct MarkdownTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable {
        case leading, center, trailing
    }

    /// Sütun başına hiza; `columnCount` bunun uzunluğudur.
    public let alignments: [Alignment]
    public let header: [[MarkdownInline]]
    /// Her satır `columnCount` hücreye tamamlanır (eksik hücre boş içeriktir).
    public let rows: [[[MarkdownInline]]]

    public init(alignments: [Alignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }

    public var columnCount: Int { alignments.count }
}

public indirect enum MarkdownInline: Sendable, Equatable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(destination: String?, content: [MarkdownInline])
    /// Görsel bu sürümde yüklenmez; alt metni ve hedefi taşınır.
    case image(source: String?, alt: String)
    /// Kaynakta tek `\n` — GitHub gibi boşluk olarak çizilir.
    case softBreak
    /// İki boşluk / `\` ile sert satır sonu.
    case lineBreak
    case html(String)
}

extension MarkdownInline {
    /// Biçimsiz düz metin (erişilebilirlik etiketi, arama, test).
    public var plainText: String {
        switch self {
        case .text(let text), .code(let text), .html(let text): return text
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return children.plainText
        case .link(_, let content): return content.plainText
        case .image(_, let alt): return alt
        case .softBreak: return " "
        case .lineBreak: return "\n"
        }
    }
}

extension Array where Element == MarkdownInline {
    public var plainText: String { map(\.plainText).joined() }
}

/// Markdown metni → `MarkdownDocument` dikişi. Saf ve senkron: döküman
/// boyutu FileViewer'ın 8 MB okuma sınırıyla kapalıdır; çağıran ayrıştırmayı
/// içerik değişince bir kez yapar.
public protocol MarkdownParsing: Sendable {
    func parse(_ text: String) -> MarkdownDocument
}
