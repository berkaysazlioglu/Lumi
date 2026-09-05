import Foundation
import LumiKit
import Observation

/// Bir sağlayıcının (Claude/Codex) kullanım snapshot'ının store'u (design/05 §6).
/// Servis sonucu buraya yazılır, UI `@Observable` ile dinler (Combine yok).
/// Tek-yön: servis → store → UI. Sağlayıcı başına bir örnek yaşar.
///
/// Yenileme MANUEL (kullanıcı kararı 2026-06-12: auto-refresh YOK). Yine de art
/// arda tıklama spam'ine karşı minimum aralık (`minRefreshInterval`) zorlanır
/// (design/05 §cache). Hata/timeout son başarılı snapshot'ı KORUR — ekran
/// boşaltılmaz; hata `errorMessage` ile görünür kılınır (karar 5).
///
/// **Kapalı gösterge hiç istek atmaz (karar 32):** `isEnabled` false iken hem
/// manuel hem otomatik yol no-op'tur. Kapı burada, tek yerdedir — çağıranların
/// ayrıca kontrol etmesi gerekmez.
@Observable
@MainActor
public final class UsageStore {
    public let provider: AgentProvider
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var isLoading = false
    /// Son başarısızlığın kullanıcıya dönük mesajı (snapshot korunurken gösterilir).
    public private(set) var errorMessage: String?
    /// Topbar'da gösterilip gösterilmeyeceği + istek atılıp atılmayacağı.
    public private(set) var isEnabled = true

    /// Manuel yenileme için minimum aralık (anti-spam, design/05).
    public static let minRefreshInterval: TimeInterval = 60

    @ObservationIgnored private let service: any UsageServicing
    /// Servis zincirinde bir TTL cache varsa onun boşaltma yüzü (K38-A).
    /// Opsiyonel: cache'siz bir kaynakta store aynen çalışır (ISP —
    /// `UsageServicing` cache kavramını taşımaz).
    @ObservationIgnored private let cache: (any UsageCacheInvalidating)?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var lastAttemptAt: Date?
    @ObservationIgnored private var hasLoadedOnce = false

    public init(
        service: any UsageServicing,
        cache: (any UsageCacheInvalidating)? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.provider = service.provider
        self.service = service
        self.cache = cache
        self.now = now
    }

    /// Topbar göstergesinin gösterdiği değer (5 saatlik oturum yüzdesi).
    public var fiveHourPercent: Int? { snapshot?.fiveHour?.percentUsed }

    /// Durum satırının TEK kaynağı (refactor 7.5/7.9). Topbar popover'ı ve
    /// Settings satırı aynı üçlüyü iki farklı kuralla türetiyordu; sıra artık
    /// burada bir kez kararlaştırılır. `.staleWithError` ayrı bir hâldir:
    /// snapshot korunurken hata gizlenmez (karar 5).
    public var statusKind: UsageStatusKind {
        if isLoading { return .loading }
        if let fetchedAt = snapshot?.fetchedAt {
            guard let errorMessage else { return .updated(fetchedAt: fetchedAt) }
            return .staleWithError(fetchedAt: fetchedAt, message: errorMessage)
        }
        if let errorMessage { return .failed(message: errorMessage) }
        return .idle
    }

    /// Yenilenebilir mi? (açık + yüklenmiyor + son denemeden bu yana min aralık geçti)
    public var canRefresh: Bool {
        if !isEnabled || isLoading { return false }
        guard let last = lastAttemptAt else { return true }
        return now().timeIntervalSince(last) >= Self.minRefreshInterval
    }

    /// Config'ten gelen açık/kapalı durumu. Kapatıldığında "ilk yükleme yapıldı"
    /// bayrağı sıfırlanır: tekrar açıldığında gösterge boş kalmasın diye bir
    /// kez daha yüklenir.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled { hasLoadedOnce = false }
    }

    /// İlk açılışta bir kez (uygulama bootstrap'i tetikler); auto-refresh değil.
    public func loadInitialIfNeeded() async {
        guard isEnabled, !hasLoadedOnce else { return }
        await performFetch()
    }

    /// Kullanıcı refresh butonu; min aralık dışında ise yeniden çeker.
    ///
    /// Açık yenileme niyeti TTL cache'ini geçersizler (K38-A): aksi hâlde
    /// kullanıcı 5 dk boyunca aynı bayat yüzdeyi görür ve buton "bozuk" sanılır.
    /// Otomatik tazeleme de bu yoldan geçer; en küçük aralık (5 dk) TTL'e eşit
    /// olduğundan pratikte fazladan istek üretmez.
    public func refresh() async {
        guard canRefresh else { return }
        await cache?.invalidateCache()
        await performFetch()
    }

    private func performFetch() async {
        isLoading = true
        hasLoadedOnce = true
        lastAttemptAt = now()
        defer { isLoading = false }
        do {
            snapshot = try await service.fetch()
            errorMessage = nil
        } catch let error as LumiError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
