import Foundation

/// Tekrarlayan, iptal edilebilir tick kaynağı (watchdog heartbeat'i).
/// Testler sahte implementasyonla tick'i elle sürer.
protocol HeartbeatScheduling: AnyObject, Sendable {
    func start(interval: TimeInterval, tick: @escaping @Sendable () -> Void)
    func stop()
}

/// io queue üzerinde koşan gerçek implementasyon (`DispatchSourceTimer`).
/// `stop()` idempotent'tir; askıdaki timer release edilmez (libdispatch trap'i).
final class DispatchHeartbeatScheduler: HeartbeatScheduling, @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(interval: TimeInterval, tick: @escaping @Sendable () -> Void) {
        stop()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        source.setEventHandler(handler: tick)
        lock.lock()
        timer = source
        lock.unlock()
        source.resume()
    }

    func stop() {
        lock.lock()
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
    }

    deinit {
        timer?.cancel()
    }
}
