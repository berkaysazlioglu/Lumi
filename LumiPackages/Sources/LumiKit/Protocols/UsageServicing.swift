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
