import Foundation

/// Donma gözetimi (design/00 Ek A §A.2-10 — Faz 4.2'ye kadar implemente
/// edilmemişti). İki işi vardır:
///
/// 1. **Stall tespiti:** in-flight byte varken (PTY okundu ama emülatöre
///    ulaşmadı) son başarılı feed'in üzerinden `stallThreshold` geçtiyse
///    terminal donmuş sayılır; sinyal UI'a "stalled" rozeti olarak çıkar
///    (siyah/boş kart yerine görünür durum). Feed geri gelince ya da in-flight
///    boşalınca kurtulma sinyali yayınlanır.
/// 2. **Adaptif batching:** feed 4 ms bütçeyi aşarsa `AdaptiveBatchBudget`
///    üzerinden coalescer eşiği yarıya iner, normale dönünce kademeli açılır.
///
/// MainActor'dan (`measureFeed`) ve io queue'dan (heartbeat) dokunulur — lock korumalı.
final class FeedWatchdog: @unchecked Sendable {
    static let defaultStallThreshold: TimeInterval = 2
    static let defaultHeartbeatInterval: TimeInterval = 2
    /// Frame bütçesinin (16 ms) dörtte biri: feed tek başına bundan uzun
    /// sürerse batch küçültülür (design/01 §8).
    static let feedBudget: TimeInterval = 0.004

    /// `true` → donma başladı, `false` → düzeldi. Yalnız DEĞİŞİMDE çağrılır.
    var onStallChange: (@Sendable (Bool) -> Void)?

    private let clock: any MonotonicClock
    private let heartbeat: any HeartbeatScheduling
    private let budget: AdaptiveBatchBudget
    private let inFlight: @Sendable () -> Int
    private let stallThreshold: TimeInterval
    private let heartbeatInterval: TimeInterval

    private let lock = NSLock()
    private var lastFeedAt: TimeInterval
    private var stalled = false

    init(
        clock: any MonotonicClock = SystemMonotonicClock(),
        heartbeat: any HeartbeatScheduling,
        budget: AdaptiveBatchBudget,
        inFlight: @escaping @Sendable () -> Int,
        stallThreshold: TimeInterval = FeedWatchdog.defaultStallThreshold,
        heartbeatInterval: TimeInterval = FeedWatchdog.defaultHeartbeatInterval
    ) {
        self.clock = clock
        self.heartbeat = heartbeat
        self.budget = budget
        self.inFlight = inFlight
        self.stallThreshold = stallThreshold
        self.heartbeatInterval = heartbeatInterval
        self.lastFeedAt = clock.now
    }

    var isStalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stalled
    }

    func start() {
        lock.lock()
        lastFeedAt = clock.now
        lock.unlock()
        heartbeat.start(interval: heartbeatInterval) { [weak self] in
            self?.tick()
        }
    }

    func stop() {
        heartbeat.stop()
    }

    /// Feed'i ölçer: süreyi bütçeye, zaman damgasını stall tespitine yazar.
    @discardableResult
    func measureFeed<Value>(_ body: () -> Value) -> Value {
        let started = clock.now
        let value = body()
        noteFeed(duration: clock.now - started)
        return value
    }

    /// Ölçüm dışarıda yapıldıysa (test) doğrudan bildirilebilir.
    func noteFeed(duration: TimeInterval) {
        if duration > Self.feedBudget {
            budget.noteOverrun()
        } else {
            budget.noteWithinBudget()
        }
        lock.lock()
        lastFeedAt = clock.now
        let wasStalled = stalled
        stalled = false
        lock.unlock()
        if wasStalled { onStallChange?(false) }
    }

    /// Heartbeat değerlendirmesi (io queue). Testler doğrudan çağırır.
    func tick() {
        let pending = inFlight()
        let elapsed: TimeInterval
        lock.lock()
        elapsed = clock.now - lastFeedAt
        let wasStalled = stalled
        let isStalling = pending > 0 && elapsed > stallThreshold
        stalled = isStalling
        lock.unlock()
        guard isStalling != wasStalled else { return }
        onStallChange?(isStalling)
    }
}
