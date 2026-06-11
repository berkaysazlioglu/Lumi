import XCTest
@testable import LumiTerminal

/// Deterministik coalescer testleri için manuel tetiklenen zamanlayıcı.
final class TestScheduler: OneShotScheduling {
    private(set) var lastInterval: TimeInterval?
    private(set) var scheduleCount = 0
    private var block: (() -> Void)?

    var isScheduled: Bool { block != nil }

    func schedule(after interval: TimeInterval, _ block: @escaping () -> Void) {
        lastInterval = interval
        scheduleCount += 1
        self.block = block
    }

    func cancel() {
        block = nil
        lastInterval = nil
    }

    func fire() {
        let pending = block
        block = nil
        pending?()
    }
}

final class OutputCoalescerTests: XCTestCase {
    private var scheduler = TestScheduler()
    private var flushes: [Data] = []

    private func makeCoalescer(sizeThreshold: Int = OutputCoalescer.defaultSizeThreshold) -> OutputCoalescer {
        scheduler = TestScheduler()
        flushes = []
        let coalescer = OutputCoalescer(scheduler: scheduler, sizeThreshold: sizeThreshold)
        coalescer.onFlush = { [weak self] data in
            self?.flushes.append(data)
        }
        return coalescer
    }

    func testCoalescesUntilTimerFires() {
        let coalescer = makeCoalescer()
        coalescer.ingest(Data("a".utf8))
        coalescer.ingest(Data("b".utf8))
        XCTAssertTrue(flushes.isEmpty)
        scheduler.fire()
        XCTAssertEqual(flushes, [Data("ab".utf8)])
    }

    func testTimerNotRescheduledWhileActive() {
        let coalescer = makeCoalescer()
        coalescer.ingest(Data("a".utf8))
        coalescer.ingest(Data("b".utf8))
        XCTAssertEqual(scheduler.scheduleCount, 1)
    }

    func testVisibleIntervalUsedByDefault() {
        let coalescer = makeCoalescer()
        coalescer.ingest(Data("x".utf8))
        XCTAssertEqual(scheduler.lastInterval, OutputCoalescer.defaultVisibleInterval)
    }

    func testHiddenIntervalWhenHidden() {
        let coalescer = makeCoalescer()
        coalescer.setHidden(true)
        coalescer.ingest(Data("x".utf8))
        XCTAssertEqual(scheduler.lastInterval, OutputCoalescer.defaultHiddenInterval)
    }

    func testSizeThresholdFlushesImmediately() {
        let coalescer = makeCoalescer(sizeThreshold: 4)
        coalescer.ingest(Data("abcde".utf8))
        XCTAssertEqual(flushes, [Data("abcde".utf8)])
        XCTAssertFalse(scheduler.isScheduled)
    }

    func testFlushNowDrainsAndCancels() {
        let coalescer = makeCoalescer()
        coalescer.ingest(Data("abc".utf8))
        coalescer.flushNow()
        XCTAssertEqual(flushes, [Data("abc".utf8)])
        XCTAssertFalse(scheduler.isScheduled)
    }

    func testEmptyBufferProducesNoFlush() {
        let coalescer = makeCoalescer()
        coalescer.flushNow()
        XCTAssertTrue(flushes.isEmpty)
    }

    func testNewBatchAfterFlushSchedulesAgain() {
        let coalescer = makeCoalescer()
        coalescer.ingest(Data("a".utf8))
        scheduler.fire()
        coalescer.ingest(Data("b".utf8))
        XCTAssertEqual(scheduler.scheduleCount, 2)
        scheduler.fire()
        XCTAssertEqual(flushes, [Data("a".utf8), Data("b".utf8)])
    }
}
