import Foundation

/// Bir sağlayıcının (Claude/Codex) kullanım verisini çeken servis sınırı
/// (design/05 §6). Yalnız I/O + parse; iş mantığı/UI yok. Hata tek tip
/// sözleşmeyle (`LumiError`) fırlatılır (karar 5) — `.cliNotFound` /
/// `.usageUnavailable`. Payload `Sendable`.
public protocol UsageServicing: Sendable {
    /// Bu servisin kullanım verisini çektiği sağlayıcı — store ve UI etiketi
    /// (ikon, başlık) bundan türetilir.
    var provider: AgentProvider { get }

    /// Sağlayıcıya özgü kaynaktan snapshot çeker. Başarısızlıkta `LumiError`.
    func fetch() async throws -> UsageSnapshot
}

/// Kullanım verisi kaynağının cache'ini boşaltabilme yeteneği (K38-A).
///
/// **Neden ayrı protokol (ISP):** `UsageServicing` "bir snapshot getir"
/// sözleşmesidir; cache bir dekoratör detayıdır. `ClaudeUsageService` /
/// `CodexUsageService` gibi cache'siz kaynakların bu üyeyi (boş da olsa)
/// taşıması, sözleşmeyi kullanmayan implementasyonlara bağımlılık yükler.
/// Ayrı ve tek üyeli bir protokol, "kullanıcı açıkça yeniledi → bir sonraki
/// okuma taze olmalı" niyetini yalnız onu gerçekten karşılayabilen tiplere
/// bağlar.
public protocol UsageCacheInvalidating: Sendable {
    /// Bir sonraki `fetch()`'in kaynağa gitmesini garantiler.
    func invalidateCache() async
}
