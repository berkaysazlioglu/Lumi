import Foundation

/// Elle ilerletilen `Clock` — TTL/zamanaşımı testlerinde gerçek beklemeyi
/// ortadan kaldırır. `sleep` anında döner; zaman yalnız `advance(by:)` ile akar.
public final class ManualClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public init(offset: Duration) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)

    public init() {}

    public var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
    }

    public func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        lock.unlock()
    }
}
