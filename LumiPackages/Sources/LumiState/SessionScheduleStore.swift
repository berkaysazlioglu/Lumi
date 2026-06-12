import Foundation
import LumiKit
import Observation

/// Günlük zamanlanmış oturum tetikleyicisi (kullanıcı kararı: belirli saatte
/// 5 saatlik Claude kullanım penceresini başlat). Uygulama açıkken her gün
/// `trigger.hour:minute` saatinde, `SessionStarterServicing` üzerinden headless
/// bir `claude -p "<prompt>"` isteği atar.
///
/// Tasarım: çalışan terminallere DOKUNMAZ — usage göstergesiyle aynı yaklaşım,
/// arka planda tek seferlik binary spawn'ı (kullanıcı kararı). Hedef seçimi,
/// "bekleyen oturum" gating'i yok; tetikleme her zaman bağımsız bir istektir.
@Observable
@MainActor
public final class SessionScheduleStore {
    /// Son tetiklemenin sonucu (UI durum satırı için).
    public enum LastRun: Sendable, Equatable {
        case success(Date)
        case failure(String, Date)
    }

    /// Bir sonraki planlanan tetikleme zamanı (UI'da göstermek için). Kapalıysa nil.
    public private(set) var nextFireDate: Date?
    /// Şu an bir `claude -p` isteği uçuyor mu (buton spinner/disable için).
    public private(set) var isStarting = false
    /// En son tetiklemenin sonucu.
    public private(set) var lastRun: LastRun?

    @ObservationIgnored private let starter: any SessionStarterServicing
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var trigger: SessionTrigger = .defaults
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    public init(
        starter: any SessionStarterServicing,
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.starter = starter
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Yaşam döngüsü

    /// Tetikleyici ayarını uygular ve zamanlamayı yeniden kurar. Boot'ta ve her
    /// config değişiminde (ConfigSideEffectCoordinator köprüsü) çağrılır.
    public func update(_ trigger: SessionTrigger) {
        self.trigger = trigger
        reschedule()
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
        nextFireDate = nil
    }

    // MARK: - Saf yardımcı (test edilebilir)

    /// `now`'dan SONRAKİ ilk `hour:minute` anı (bugün geçtiyse yarın). DST/takvim
    /// kıvrımlarını Calendar yönetir.
    public static func nextFireDate(
        after now: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar = .current
    ) -> Date? {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }

    // MARK: - Tetikleme

    /// Tetiklemeyi hemen uygular (zamanlayıcı + "şimdi başlat" butonu ortak yolu).
    /// Aynı anda ikinci istek başlatmaz. `true` = istek başarıyla tamamlandı.
    @discardableResult
    public func fireNow() async -> Bool {
        guard !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }
        do {
            try await starter.start(prompt: trigger.effectivePrompt)
            lastRun = .success(now())
            return true
        } catch {
            let detail = (error as? LumiError)?.errorDescription ?? "\(error)"
            lastRun = .failure(detail, now())
            return false
        }
    }

    private func reschedule() {
        timerTask?.cancel()
        timerTask = nil
        guard trigger.enabled else {
            nextFireDate = nil
            return
        }
        nextFireDate = Self.nextFireDate(
            after: now(),
            hour: trigger.hour,
            minute: trigger.minute,
            calendar: calendar
        )
        timerTask = Task { @MainActor [weak self] in
            await self?.runLoop()
        }
    }

    /// Bir sonraki tetikleme anına kadar uyur, tetikler, ertesi güne yeniden
    /// kurar. Config değişince `reschedule()` bu task'ı iptal edip yenisini açar.
    private func runLoop() async {
        while !Task.isCancelled {
            guard let fireDate = Self.nextFireDate(
                after: now(),
                hour: trigger.hour,
                minute: trigger.minute,
                calendar: calendar
            ) else { return }
            nextFireDate = fireDate

            let interval = fireDate.timeIntervalSince(now())
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            if Task.isCancelled { return }

            await fireNow()

            // Aynı dakika içinde tekrar tetiklememek için pencereyi geç.
            try? await Task.sleep(for: .seconds(61))
        }
    }
}
