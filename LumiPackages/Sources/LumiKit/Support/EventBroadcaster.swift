import Foundation

/// Servis→store event dağıtımı için continuation registry'si (design/02 girişi).
/// Her `stream()` çağrısı bağımsız bir AsyncStream döner; `send` hepsine yield eder.
/// Tasarım gereği her domain'in tek tüketicisi (kendi store'u) vardır, ancak
/// testler ve geçici dinleyiciler için çoklu stream desteklenir.
public final class EventBroadcaster<Event: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private let bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy

    /// Varsayılan `.unbounded` mevcut davranışı korur (yaşam döngüsü event'leri
    /// düşük hacimli ve kayıpsız olmalı). Yüksek hacimli/drop'a toleranslı
    /// akışlar `.bufferingNewest(_:)` ile sınırlanabilir.
    public init(bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy = .unbounded) {
        self.bufferingPolicy = bufferingPolicy
    }

    public func stream() -> AsyncStream<Event> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    public func send(_ event: Event) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets {
            continuation.yield(event)
        }
    }

    public func finishAll() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets {
            continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
