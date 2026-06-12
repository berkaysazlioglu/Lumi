import Foundation
import LumiKit
import Observation

/// Claude kullanım snapshot'ının store'u (design/05 §6). Servis sonucu buraya
/// yazılır, UI `@Observable` ile dinler (Combine yok). Tek-yön: servis → store → UI.
///
/// Yenileme MANUEL (kullanıcı kararı 2026-06-12: auto-refresh YOK). Yine de art
/// arda tıklama spam'ine karşı minimum aralık (`minRefreshInterval`) zorlanır
/// (design/05 §cache). Hata/timeout son başarılı snapshot'ı KORUR — ekran
/// boşaltılmaz; hata `errorMessage` ile görünür kılınır (karar 5).
@Observable
@MainActor
public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var isLoading = false
    /// Son başarısızlığın kullanıcıya dönük mesajı (snapshot korunurken gösterilir).
    public private(set) var errorMessage: String?

    /// Manuel yenileme için minimum aralık (anti-spam, design/05).
    public static let minRefreshInterval: TimeInterval = 60

    @ObservationIgnored private let service: any UsageServicing
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var lastAttemptAt: Date?
    @ObservationIgnored private var hasLoadedOnce = false

    public init(service: any UsageServicing, now: @escaping @MainActor () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    /// Topbar göstergesinin gösterdiği değer (5 saatlik oturum yüzdesi).
    public var fiveHourPercent: Int? { snapshot?.fiveHour?.percentUsed }

    /// Yenilenebilir mi? (yüklenmiyor + son denemeden bu yana min aralık geçti)
    public var canRefresh: Bool {
        if isLoading { return false }
        guard let last = lastAttemptAt else { return true }
        return now().timeIntervalSince(last) >= Self.minRefreshInterval
    }

    /// İlk açılışta bir kez (uygulama bootstrap'i tetikler); auto-refresh değil.
    public func loadInitialIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await performFetch()
    }

    /// Kullanıcı refresh butonu; min aralık dışında ise yeniden çeker.
    public func refresh() async {
        guard canRefresh else { return }
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
