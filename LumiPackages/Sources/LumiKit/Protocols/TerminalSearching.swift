import Foundation

/// Terminal içi arama motoru (karar 144 — Orca `TerminalSearch` paritesi).
///
/// Canlı emülatör buffer'ını (scrollback dahil) tarar, eşleşmeleri terminalin
/// üstünde vurgular ve etkin eşleşmeyi görünür alana kaydırır. Çubuğun
/// durumu (sorgu, seçenekler, sayaç) `TerminalSearchStore`'dadır; motor
/// yalnız buffer'ı bilir.
@MainActor
public protocol TerminalSearching: AnyObject {
    /// Sorguyu çalıştırır ve etkin eşleşmeyi `step`'e göre seçer. Bilinmeyen
    /// terminal ya da sorgusuz istek `.empty` döner (ve vurguyu temizler).
    @discardableResult
    func search(_ id: TerminalID, query: TerminalSearchQuery, step: TerminalSearchStep) -> TerminalSearchSummary

    /// Vurguları ve aramanın durumunu bırakır. Bilinmeyen terminal → no-op.
    func clearSearch(_ id: TerminalID)

    /// Arama açıkken terminalin içeriği değişti ve sayım yeniden yapıldı
    /// (çıktı akışı, kaydırma ile kırpılan satırlar, yeniden boyutlanma).
    var onSearchResultsChanged: ((TerminalID, TerminalSearchSummary) -> Void)? { get set }
}
