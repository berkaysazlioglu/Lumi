import Foundation

/// Tek atımlık, yeniden kurulabilir zamanlayıcı soyutlaması.
/// Coalescer ve silence-timer testlerinin deterministik koşması için enjekte edilir.
protocol OneShotScheduling: AnyObject {
    func schedule(after interval: TimeInterval, _ block: @escaping () -> Void)
    func cancel()
}

/// io queue üzerinde çalışan gerçek implementasyon. Queue-confined kullanılır.
final class DispatchOneShotScheduler: OneShotScheduling {
    private let queue: DispatchQueue
    private var pending: DispatchWorkItem?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func schedule(after interval: TimeInterval, _ block: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: block)
        pending = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
