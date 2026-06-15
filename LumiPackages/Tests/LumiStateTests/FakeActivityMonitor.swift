import Foundation
import LumiKit

/// ActivityMonitoring test ikamesi (design/00 §3 deseni). idle değeri test
/// içinde kontrol edilir — idle-gate'in aktif/pasif dalları doğrulanır.
final class FakeActivityMonitor: ActivityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var idle: TimeInterval

    init(idleSeconds: TimeInterval) {
        self.idle = idleSeconds
    }

    func setIdleSeconds(_ value: TimeInterval) {
        lock.withLock { idle = value }
    }

    func secondsSinceUserInput() -> TimeInterval {
        lock.withLock { idle }
    }
}
