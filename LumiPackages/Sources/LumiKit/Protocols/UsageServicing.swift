import Foundation

/// Claude kullanım göstergesinin servis sınırı (design/05 §6). Yalnız I/O +
/// parse; iş mantığı/UI yok. Hata tek tip sözleşmeyle (`LumiError`) fırlatılır
/// (karar 5) — `.cliNotFound` / `.usageUnavailable`. Payload `Sendable`.
public protocol UsageServicing: Sendable {
    /// `claude -p "/usage"` spawn → stdout → parse. Başarısızlıkta `LumiError`.
    func fetch() async throws -> UsageSnapshot
}
