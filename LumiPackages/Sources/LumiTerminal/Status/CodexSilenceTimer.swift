import Foundation

/// Codex fallback status tespiti: 3 sn output sessizliği → onSilence (spec/10 §6).
/// Yalnızca hint==codex iken touch edilir; hint claude'a dönünce cancel edilir.
final class CodexSilenceTimer {
    static let defaultInterval: TimeInterval = 3.0

    var onSilence: (() -> Void)?
    private let scheduler: OneShotScheduling
    private let interval: TimeInterval

    init(scheduler: OneShotScheduling, interval: TimeInterval = CodexSilenceTimer.defaultInterval) {
        self.scheduler = scheduler
        self.interval = interval
    }

    func touch() {
        scheduler.schedule(after: interval) { [weak self] in
            self?.onSilence?()
        }
    }

    func cancel() {
        scheduler.cancel()
    }
}
