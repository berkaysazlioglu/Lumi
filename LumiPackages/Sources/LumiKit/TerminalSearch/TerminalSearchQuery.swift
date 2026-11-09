import Foundation

/// Terminal içi aramanın sorgusu (karar 144 — Orca `TerminalSearch` paritesi).
///
/// Metin + iki anahtar (büyük/küçük harf, regex). Arama motoru yalnız
/// `requestText` doluyken koşar: boş ya da sınırı aşan sorgu "arama yok"tur.
public struct TerminalSearchQuery: Equatable, Sendable {
    /// Orca `FIND_QUERY_MAX_BYTES`: yapıştırılan dev bir metin her tuşta
    /// scrollback boyu taranıp ana thread'i kilitlemesin.
    public static let maxBytes = 2 * 1024

    public var text: String
    public var isCaseSensitive: Bool
    public var isRegex: Bool

    public init(text: String = "", isCaseSensitive: Bool = false, isRegex: Bool = false) {
        self.text = text
        self.isCaseSensitive = isCaseSensitive
        self.isRegex = isRegex
    }

    /// Motora gidecek metin; boş ya da sınır üstü sorguda `nil`.
    public var requestText: String? {
        guard !text.isEmpty, !isTooLarge else { return nil }
        return text
    }

    public var isTooLarge: Bool {
        text.utf8.count > Self.maxBytes
    }
}

/// Aramanın o anki sonucu: kaçıncı eşleşmede olunduğu ve toplam.
public struct TerminalSearchSummary: Equatable, Sendable {
    /// Etkin eşleşmenin 0 tabanlı sırası; eşleşme yoksa `nil`.
    public var activeIndex: Int?
    public var count: Int
    /// Sayım `TerminalSearchMatcher.matchLimit`'te kesildi — gerçek toplam daha büyük.
    public var isCapped: Bool

    public init(activeIndex: Int? = nil, count: Int = 0, isCapped: Bool = false) {
        self.activeIndex = activeIndex
        self.count = count
        self.isCapped = isCapped
    }

    public static let empty = TerminalSearchSummary()

    /// Arama çubuğundaki sayaç (Orca): sorgu yokken `0/0`, eşleşme yoksa
    /// `No results`, varsa `3/14` — sayım kesildiyse toplamın ardında `+`.
    public func statusText(hasQuery: Bool) -> String {
        guard hasQuery else { return "0/0" }
        guard count > 0 else { return "No results" }
        let total = isCapped ? "\(count)+" : "\(count)"
        guard let activeIndex else { return total }
        return "\(activeIndex + 1)/\(total)"
    }
}

/// Aramanın bir adımı.
public enum TerminalSearchStep: Equatable, Sendable {
    /// Sorgu ya da seçenek değişti: etkin eşleşme hâlâ geçerliyse yerinde
    /// kalır, değilse görünür alana en yakın eşleşmeye geçilir.
    case incremental
    case next
    case previous
}
