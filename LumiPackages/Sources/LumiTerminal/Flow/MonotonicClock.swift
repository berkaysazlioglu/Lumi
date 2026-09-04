import Foundation

/// Duvar saatinden bağımsız, geriye gitmeyen zaman kaynağı.
/// Watchdog testleri sahte bir clock'la deterministik koşar.
protocol MonotonicClock: Sendable {
    /// Keyfi bir başlangıca göre saniye cinsinden geçen süre.
    var now: TimeInterval { get }
}

/// Üretim implementasyonu: `DispatchTime` (uptime, NTP sıçramalarından etkilenmez).
struct SystemMonotonicClock: MonotonicClock {
    var now: TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
