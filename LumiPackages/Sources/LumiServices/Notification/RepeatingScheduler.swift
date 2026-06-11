import Foundation

/// Terminal başına tekrar bildirimleri için zamanlayıcı soyutlaması.
/// NotificationService testlerinin deterministik koşması için enjekte edilir.
@MainActor
protocol RepeatingScheduling: AnyObject {
    func schedule(id: String, interval: TimeInterval, _ tick: @escaping @MainActor () -> Void)
    func cancel(id: String)
    var activeIDs: Set<String> { get }
}

@MainActor
final class TimerRepeatingScheduler: RepeatingScheduling {
    private var timers: [String: Timer] = [:]

    var activeIDs: Set<String> {
        Set(timers.keys)
    }

    func schedule(id: String, interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) {
        cancel(id: id)
        timers[id] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick()
            }
        }
    }

    func cancel(id: String) {
        timers.removeValue(forKey: id)?.invalidate()
    }
}
