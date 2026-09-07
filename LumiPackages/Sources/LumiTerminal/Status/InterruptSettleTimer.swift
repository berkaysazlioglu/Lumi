import Foundation

/// Kesme çıkarımı zamanlayıcısı (karar 45; Orca `AGENT_INTERRUPT_SETTLE_MS`).
///
/// Ajan `working`ken kullanıcı tek başına Esc ya da Ctrl+C gönderirse turn
/// kesilir; Claude yeni sürümlerde `Stop{is_interrupt}` yayar ama Codex ve
/// eski Claude kesme hook'unu kaçırabilir. Pencere dolup hook gelmezse
/// `onSettle` tetiklenir; herhangi bir hook olayı `cancel()` ile çıkarımı
/// iptal eder (gerçek sinyal kazanır).
///
/// Yalnız `hookReducer.isBound` iken dokunulur; io queue'ya confine.
final class InterruptSettleTimer {
    static let defaultInterval: TimeInterval = 0.5

    var onSettle: (() -> Void)?
    private let scheduler: OneShotScheduling
    private let interval: TimeInterval

    init(scheduler: OneShotScheduling, interval: TimeInterval = InterruptSettleTimer.defaultInterval) {
        self.scheduler = scheduler
        self.interval = interval
    }

    func touch() {
        scheduler.schedule(after: interval) { [weak self] in
            self?.onSettle?()
        }
    }

    func cancel() {
        scheduler.cancel()
    }

    /// Tek başına ESC (0x1B) ya da Ctrl+C (0x03) mı — ESC ile başlayan bir
    /// tuş dizisi (ok tuşları vb.) kesme değildir.
    static func isInterruptKeystroke(_ data: Data) -> Bool {
        guard data.count == 1, let byte = data.first else { return false }
        return byte == 0x1B || byte == 0x03
    }
}
