import Foundation
import LumiKit

/// `ActivityMonitoring` test ikamesi (design/00 §3 deseni). idle değeri test
/// içinde kontrol edilir — idle-gate'in aktif/pasif dalları doğrulanır.
public final class FakeActivityMonitor: ActivityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var idle: TimeInterval
    private var queryCount = 0

    public init(idleSeconds: TimeInterval) {
        self.idle = idleSeconds
    }

    public func setIdleSeconds(_ value: TimeInterval) {
        lock.withLock { idle = value }
    }

    /// `secondsSinceUserInput` kaç kez sorgulandı.
    public var callCount: Int {
        lock.withLock { queryCount }
    }

    public func secondsSinceUserInput() -> TimeInterval {
        lock.withLock {
            queryCount += 1
            return idle
        }
    }
}
