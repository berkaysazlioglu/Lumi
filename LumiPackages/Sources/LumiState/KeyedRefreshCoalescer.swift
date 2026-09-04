import Foundation

/// Anahtar başına "uçuşta ise atla, bitince bir kez daha" yenileme koalesansı
/// (karar 28). FSEvents üreticisi (~4 event/sn) yavaş bir tüketiciden (tam
/// file-tree taraması) hızlıysa kuyruk şişmez: uçuş sırasında gelen N istek
/// tek bir follow-up taramaya çöker, böylece ağaç daima son duruma yakınsar.
@MainActor
public final class KeyedRefreshCoalescer {
    public typealias Perform = @MainActor (String) async -> Void

    private let perform: Perform
    private var inFlight: Set<String> = []
    private var pending: Set<String> = []

    public init(perform: @escaping Perform) {
        self.perform = perform
    }

    public func request(_ key: String) {
        if inFlight.contains(key) {
            pending.insert(key)
            return
        }
        inFlight.insert(key)
        Task { @MainActor [weak self] in
            await self?.drain(key)
        }
    }

    public func isInFlight(_ key: String) -> Bool {
        inFlight.contains(key)
    }

    private func drain(_ key: String) async {
        repeat {
            await perform(key)
        } while pending.remove(key) != nil
        inFlight.remove(key)
    }
}
