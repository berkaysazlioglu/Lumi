import Foundation
import XCTest
@testable import LumiTerminal

/// design/00 Ek A §A.2-10 donma gözetimi. Clock ve heartbeat enjekte edilir →
/// 2 sn beklenmez, tick'ler elle sürülür.
final class FeedWatchdogTests: XCTestCase {
    private static let threshold: TimeInterval = 2

    private func makeWatchdog(
        clock: TestClock = TestClock(),
        heartbeat: TestHeartbeat = TestHeartbeat(),
        budget: AdaptiveBatchBudget = AdaptiveBatchBudget(
            defaultThreshold: 128 * 1024,
            minimumThreshold: 8 * 1024
        ),
        inFlight: InFlightStub = InFlightStub()
    ) -> (FeedWatchdog, TestClock, TestHeartbeat, AdaptiveBatchBudget, InFlightStub) {
        let watchdog = FeedWatchdog(
            clock: clock,
            heartbeat: heartbeat,
            budget: budget,
            inFlight: { inFlight.value },
            stallThreshold: Self.threshold,
            heartbeatInterval: Self.threshold
        )
        return (watchdog, clock, heartbeat, budget, inFlight)
    }

    // MARK: - Stall tespiti

    /// In-flight byte var ve eşikten uzun süredir feed yok → donma sinyali.
    func testStallIsReportedWhenInFlightBytesStopBeingFed() {
        // Arrange
        let (watchdog, clock, heartbeat, _, inFlight) = makeWatchdog()
        let signals = SignalRecorder()
        watchdog.onStallChange = { signals.append($0) }
        watchdog.start()

        // Act — okundu ama beslenmedi; eşik aşılana dek sinyal yok
        inFlight.value = 64 * 1024
        clock.advance(by: Self.threshold - 0.1)
        heartbeat.tick()
        XCTAssertEqual(signals.values, [], "eşik dolmadan donma bildirildi")

        clock.advance(by: 0.2)
        heartbeat.tick()

        // Assert
        XCTAssertEqual(signals.values, [true])
        XCTAssertTrue(watchdog.isStalled)
    }

    /// In-flight boşsa (akacak veri yok) sessizlik donma değildir.
    func testIdleTerminalIsNotStalled() {
        let (watchdog, clock, heartbeat, _, _) = makeWatchdog()
        let signals = SignalRecorder()
        watchdog.onStallChange = { signals.append($0) }
        watchdog.start()

        clock.advance(by: Self.threshold * 10)
        heartbeat.tick()

        XCTAssertEqual(signals.values, [])
        XCTAssertFalse(watchdog.isStalled)
    }

    func testStallIsReportedOnlyOnceUntilRecovery() {
        let (watchdog, clock, heartbeat, _, inFlight) = makeWatchdog()
        let signals = SignalRecorder()
        watchdog.onStallChange = { signals.append($0) }
        watchdog.start()
        inFlight.value = 1

        clock.advance(by: Self.threshold + 1)
        heartbeat.tick()
        heartbeat.tick()
        heartbeat.tick()

        XCTAssertEqual(signals.values, [true], "her heartbeat'te tekrar bildirildi")
    }

    // MARK: - Kurtulma

    func testFeedRecoversFromStall() {
        let (watchdog, clock, heartbeat, _, inFlight) = makeWatchdog()
        let signals = SignalRecorder()
        watchdog.onStallChange = { signals.append($0) }
        watchdog.start()
        inFlight.value = 1
        clock.advance(by: Self.threshold + 1)
        heartbeat.tick()

        // Act — emülatör yeniden beslendi
        watchdog.noteFeed(duration: 0.001)

        XCTAssertEqual(signals.values, [true, false])
        XCTAssertFalse(watchdog.isStalled)
    }

    /// In-flight boşalırsa (batch drop edildi / PTY kapandı) da kurtulunur.
    func testDrainedInFlightRecoversFromStall() {
        let (watchdog, clock, heartbeat, _, inFlight) = makeWatchdog()
        let signals = SignalRecorder()
        watchdog.onStallChange = { signals.append($0) }
        watchdog.start()
        inFlight.value = 1
        clock.advance(by: Self.threshold + 1)
        heartbeat.tick()

        inFlight.value = 0
        heartbeat.tick()

        XCTAssertEqual(signals.values, [true, false])
    }

    // MARK: - Adaptif batching (>4 ms bütçe)

    func testFeedOverBudgetHalvesBatchThreshold() {
        let budget = AdaptiveBatchBudget(defaultThreshold: 128 * 1024, minimumThreshold: 8 * 1024)
        let (watchdog, _, _, _, _) = makeWatchdog(budget: budget)

        watchdog.noteFeed(duration: FeedWatchdog.feedBudget + 0.001)

        XCTAssertEqual(budget.threshold, 64 * 1024)
    }

    func testRepeatedOverrunsStopAtMinimumThreshold() {
        let budget = AdaptiveBatchBudget(defaultThreshold: 128 * 1024, minimumThreshold: 8 * 1024)
        let (watchdog, _, _, _, _) = makeWatchdog(budget: budget)

        for _ in 0 ..< 20 {
            watchdog.noteFeed(duration: 0.05)
        }

        XCTAssertEqual(budget.threshold, 8 * 1024, "alt sınır aşıldı")
    }

    func testWithinBudgetFeedsRestoreThresholdGradually() {
        let budget = AdaptiveBatchBudget(defaultThreshold: 128 * 1024, minimumThreshold: 8 * 1024)
        let (watchdog, _, _, _, _) = makeWatchdog(budget: budget)
        watchdog.noteFeed(duration: 0.05)
        watchdog.noteFeed(duration: 0.05)
        XCTAssertEqual(budget.threshold, 32 * 1024)

        // Act — kademeli geri açılış: tek adımda default'a sıçramaz
        watchdog.noteFeed(duration: 0.001)
        XCTAssertEqual(budget.threshold, 64 * 1024)
        watchdog.noteFeed(duration: 0.001)
        XCTAssertEqual(budget.threshold, 128 * 1024)

        // Act — default'un üstüne çıkmaz
        watchdog.noteFeed(duration: 0.001)
        XCTAssertEqual(budget.threshold, 128 * 1024)
    }

    /// `measureFeed` süreyi kendi clock'undan ölçer ve bütçeye uygular.
    func testMeasureFeedAppliesMeasuredDurationToBudget() {
        let clock = TestClock()
        let budget = AdaptiveBatchBudget(defaultThreshold: 128 * 1024, minimumThreshold: 8 * 1024)
        let (watchdog, _, _, _, _) = makeWatchdog(clock: clock, budget: budget)

        let result = watchdog.measureFeed { () -> Int in
            clock.advance(by: FeedWatchdog.feedBudget * 2)
            return 42
        }

        XCTAssertEqual(result, 42)
        XCTAssertEqual(budget.threshold, 64 * 1024)
    }

    /// Coalescer eşiği watchdog'un bütçesinden okunur (canlı knob).
    func testCoalescerFlushesEarlierAfterBudgetOverrun() {
        let scheduler = TestScheduler()
        let budget = AdaptiveBatchBudget(defaultThreshold: 1024, minimumThreshold: 256)
        let coalescer = OutputCoalescer(scheduler: scheduler, sizeThreshold: 1024, budget: budget)
        let flushes = SignalRecorder()
        coalescer.onFlush = { _ in flushes.append(true) }

        coalescer.ingest(Data(repeating: 0x61, count: 600))
        XCTAssertEqual(flushes.values.count, 0, "eşik altında flush olmamalı")

        budget.noteOverrun() // 1024 → 512; birikmiş 600 byte artık eşiğin üstünde
        coalescer.ingest(Data(repeating: 0x61, count: 1))
        XCTAssertEqual(flushes.values.count, 1, "küçültülmüş eşik uygulanmadı")
    }

    // MARK: - Yaşam döngüsü

    func testStartAndStopDriveHeartbeat() {
        let (watchdog, _, heartbeat, _, _) = makeWatchdog()

        watchdog.start()
        XCTAssertTrue(heartbeat.isRunning)
        XCTAssertEqual(heartbeat.interval, Self.threshold)

        watchdog.stop()
        XCTAssertFalse(heartbeat.isRunning)
    }
}

// MARK: - Test ikameleri

final class TestClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval = 1000

    var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current += interval
        lock.unlock()
    }
}

final class TestHeartbeat: HeartbeatScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private(set) var interval: TimeInterval = 0

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handler != nil
    }

    func start(interval: TimeInterval, tick: @escaping @Sendable () -> Void) {
        lock.lock()
        self.interval = interval
        handler = tick
        lock.unlock()
    }

    func stop() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func tick() {
        lock.lock()
        let block = handler
        lock.unlock()
        block?()
    }
}

final class InFlightStub: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Bool) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
