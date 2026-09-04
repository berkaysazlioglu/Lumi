import Foundation

/// Fake servislerin `events()` abonelik sayacı. Servis→store event akışında
/// abonelik, tüketici Task'ı çalışınca kurulur; ondan önce gönderilen event'ler
/// düşer. Testler bu sayaçla abonelik penceresini bekler (plan 5.6).
public final class SubscriptionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    public init() {}

    public var value: Int { lock.withLock { count } }

    public func increment() {
        lock.withLock { count += 1 }
    }
}
