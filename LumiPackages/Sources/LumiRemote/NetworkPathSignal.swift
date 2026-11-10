import Foundation
import Network

/// "Ağ yeniden kullanılabilir oldu" sinyali (karar 147). Relay bağlantıları bunu
/// dinleyip geri çekilme beklemesini keser ve hemen yeniden dener — Mac evden ofise
/// geçince allowlist reddi (4006) ya da ağ kopması en fazla 60 sn değil, anında kalkar.
public protocol NetworkPathSignaling: Sendable {
    /// Her abone kendi akışını alır; ağ yolu `satisfied` olduğunda bir `Void` düşer.
    func changes() -> AsyncStream<Void>
}

/// `NWPathMonitor` tabanlı tek, paylaşılan izleyici. Monitor ilk aboneyle başlar ve
/// uygulama ömrünce yaşar; abonelik akış bitince kendiliğinden düşer.
public final class NetworkPathSignal: NetworkPathSignaling, @unchecked Sendable {
    public static let shared = NetworkPathSignal()

    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.lumi.network-path")

    private init() {}

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        lock.withLock {
            subscribers[id] = continuation
            startMonitorIfNeeded()
        }
        return stream
    }

    /// `lock` tutulurken çağrılır.
    private func startMonitorIfNeeded() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.broadcast()
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    private func broadcast() {
        let targets = lock.withLock { Array(subscribers.values) }
        for continuation in targets { continuation.yield() }
    }

    private func remove(_ id: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: id) }
    }
}
