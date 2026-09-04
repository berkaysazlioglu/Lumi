import Foundation
import LumiKit

/// `UsageServicing` dekoratörü (refactor 3.11): TTL içinde aynı snapshot'ı
/// döndürür, sarmaladığı servise gitmez.
///
/// Sözleşme:
/// - **Yalnız başarı cache'lenir.** Hata cache'lenmez; bir sonraki `fetch()`
///   yeniden dener (geçici bir 5xx'i TTL boyunca dondurmak, göstergeyi
///   gereksiz yere ölü tutardı).
/// - Hata anında ESKİ (hâlâ taze) cache varsa o döner: `UsageStore`'un
///   "son başarılı snapshot korunur" davranışıyla aynı yönde.
/// - Eşzamanlı çağrılar actor sayesinde serileşir; TTL içinde ikinci çağrı
///   ağa hiç çıkmaz.
///
/// **Bağlanmadı:** K38 (aralık seti / TTL) kararı verilene kadar composition
/// root'ta kullanılmaz; `UsageStore.minRefreshInterval` kapısı yerinde durur.
public actor CachingUsageService<ClockType: Clock>: UsageServicing
where ClockType.Duration == Duration {
    public nonisolated let provider: AgentProvider

    private let wrapped: any UsageServicing
    private let ttl: Duration
    private let clock: ClockType
    private var cached: (snapshot: UsageSnapshot, at: ClockType.Instant)?

    public init(wrapping wrapped: any UsageServicing, ttl: Duration, clock: ClockType) {
        self.wrapped = wrapped
        self.ttl = ttl
        self.clock = clock
        self.provider = wrapped.provider
    }

    public func fetch() async throws -> UsageSnapshot {
        if let fresh = freshSnapshot() { return fresh }
        do {
            let snapshot = try await wrapped.fetch()
            cached = (snapshot, clock.now)
            return snapshot
        } catch {
            // Hata cache'lenmez; ama elde taze bir snapshot varsa onu koru.
            if let fresh = freshSnapshot() { return fresh }
            throw error
        }
    }

    /// Cache'i elle boşaltır (kullanıcının açık "refresh" niyeti için).
    public func invalidate() {
        cached = nil
    }

    private func freshSnapshot() -> UsageSnapshot? {
        guard let cached else { return nil }
        return cached.at.duration(to: clock.now) < ttl ? cached.snapshot : nil
    }
}

extension CachingUsageService where ClockType == ContinuousClock {
    public init(wrapping wrapped: any UsageServicing, ttl: Duration) {
        self.init(wrapping: wrapped, ttl: ttl, clock: ContinuousClock())
    }
}
