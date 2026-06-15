import Foundation
import LumiKit
import Observation

/// Kullanım göstergesinin opt-in otomatik tazelenmesi (karar 20). Açıkken her
/// `intervalMinutes`'te bir, YALNIZCA kullanıcı aktifse `UsageStore.refresh()`
/// çağırır. `SessionScheduleStore` ile aynı iskelet: config'i `update(_:)` ile
/// izler, bir `Task` döngüsünde uyur/tetikler; config değişince döngü iptal edilip
/// yenisi kurulur.
///
/// **Aktiflik kapısı (idle-gate):** Tetikleme anında, son kullanıcı girdisinden
/// bu yana geçen süre aralıktan AZ ise tazelenir; değilse atlanır ("kullanıcı son
/// aralıkta aktifti" kuralı). **Uyku:** Mac uykudayken process askıya alınır →
/// döngü ateşlenemez. `Task.sleep` `ContinuousClock` kullandığından uzun uykudan
/// sonra uyanışta döngü bir kez döner; idle-gate burada da devrededir (kullanıcı
/// uyandırmak için girdi verdiyse bir kez tazeler, değilse atlar). Bu yüzden ayrı
/// bir sleep/wake bildirimi gerekmez — LumiState AppKit'ten bağımsız kalır.
@Observable
@MainActor
public final class UsageAutoRefreshStore {
    @ObservationIgnored private let usage: UsageStore
    @ObservationIgnored private let activity: any ActivityMonitoring
    @ObservationIgnored private var settings: UsageAutoRefresh = .defaults
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    public init(usage: UsageStore, activity: any ActivityMonitoring) {
        self.usage = usage
        self.activity = activity
    }

    // MARK: - Yaşam döngüsü

    /// Ayarı uygular ve döngüyü yeniden kurar. Boot'ta ve her config değişiminde
    /// (ConfigSideEffectCoordinator köprüsü) çağrılır.
    public func update(_ settings: UsageAutoRefresh) {
        self.settings = settings
        reschedule()
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Tetikleme (test edilebilir tek adım)

    /// Kullanıcı son aralık içinde aktifse usage'ı tazeler. Tazelendiyse `true`.
    /// Döngü ve testler ortak bu yolu kullanır (SessionScheduleStore.fireNow gibi).
    @discardableResult
    func performTickIfActive() async -> Bool {
        let interval = TimeInterval(settings.intervalMinutes * 60)
        guard activity.secondsSinceUserInput() < interval else { return false }
        await usage.refresh()
        return true
    }

    // MARK: - Zamanlama

    private func reschedule() {
        timerTask?.cancel()
        timerTask = nil
        guard settings.enabled else { return }
        timerTask = Task { @MainActor [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let interval = TimeInterval(settings.intervalMinutes * 60)
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            await performTickIfActive()
        }
    }
}
