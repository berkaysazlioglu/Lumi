import Foundation
import XCTest
@testable import LumiTerminal

/// Codex fallback sessizlik zamanlayıcısının touch/cancel/fire semantiği
/// (design/01 §7 "öncelikli test hedefleri"). Enjekte edilen `TestScheduler`
/// sayesinde 3 saniye beklenmez — tamamen deterministiktir.
final class CodexSilenceTimerTests: XCTestCase {
    private func makeTimer(
        interval: TimeInterval = CodexSilenceTimer.defaultInterval
    ) -> (CodexSilenceTimer, TestScheduler, () -> Int) {
        let scheduler = TestScheduler()
        let timer = CodexSilenceTimer(scheduler: scheduler, interval: interval)
        var silences = 0
        timer.onSilence = { silences += 1 }
        return (timer, scheduler, { silences })
    }

    func testTouchSchedulesWithThreeSecondDefaultInterval() {
        // Arrange
        let (timer, scheduler, _) = makeTimer()

        // Act
        timer.touch()

        // Assert — design/01 §3: codex sessizlik eşiği 3 sn
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.lastInterval, 3.0)
        XCTAssertEqual(CodexSilenceTimer.defaultInterval, 3.0)
    }

    func testInjectedIntervalIsHonored() {
        let (timer, scheduler, _) = makeTimer(interval: 0.25)

        timer.touch()

        XCTAssertEqual(scheduler.lastInterval, 0.25)
    }

    func testFireInvokesOnSilenceExactlyOnce() {
        // Arrange
        let (timer, scheduler, silences) = makeTimer()
        timer.touch()

        // Act
        XCTAssertTrue(scheduler.fire())

        // Assert — tek atımlıktır: ikinci fire'da bekleyen blok kalmamalı
        XCTAssertEqual(silences(), 1)
        XCTAssertFalse(scheduler.fire())
        XCTAssertEqual(silences(), 1)
    }

    func testRepeatedTouchReschedulesInsteadOfStacking() {
        // Arrange — her output chunk'ında touch edilir (design/01 §3)
        let (timer, scheduler, silences) = makeTimer()

        // Act
        timer.touch()
        timer.touch()
        timer.touch()

        // Assert — üç kurulum, ama bekleyen tek blok → tek sessizlik sinyali
        XCTAssertEqual(scheduler.scheduleCount, 3)
        XCTAssertTrue(scheduler.fire())
        XCTAssertFalse(scheduler.fire())
        XCTAssertEqual(silences(), 1)
    }

    func testCancelPreventsPendingSilence() {
        // Arrange
        let (timer, scheduler, silences) = makeTimer()
        timer.touch()

        // Act — hint claude'a döndü / turn-complete geldi / exit
        timer.cancel()

        // Assert
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertFalse(scheduler.isScheduled)
        XCTAssertFalse(scheduler.fire())
        XCTAssertEqual(silences(), 0)
    }

    func testCancelWithoutTouchIsSafeAndIdempotent() {
        let (timer, scheduler, silences) = makeTimer()

        timer.cancel()
        timer.cancel()

        XCTAssertEqual(scheduler.cancelCount, 2)
        XCTAssertEqual(silences(), 0)
    }

    func testTouchAfterCancelSchedulesAgain() {
        // Sessizlik sinyali iptal edildikten sonra yeni aktivite yine izlenmeli.
        let (timer, scheduler, silences) = makeTimer()

        timer.touch()
        timer.cancel()
        timer.touch()

        XCTAssertEqual(scheduler.scheduleCount, 2)
        XCTAssertTrue(scheduler.fire())
        XCTAssertEqual(silences(), 1)
    }

    func testFiringAfterOwnerDeallocationIsSilent() {
        // Oturum kapanırken bekleyen bir dispatch bloğu hâlâ kuyrukta olabilir;
        // `touch` içindeki `[weak self]` sayesinde hayalet sessizlik yayınlanmaz.
        let scheduler = TestScheduler()
        var silences = 0
        var timer: CodexSilenceTimer? = CodexSilenceTimer(scheduler: scheduler)
        timer?.onSilence = { silences += 1 }
        timer?.touch()

        timer = nil

        XCTAssertTrue(scheduler.fire(), "blok yine de çalışır (dispatch iptal edilmedi)")
        XCTAssertEqual(silences, 0, "ölü timer sessizlik yayınladı")
    }
}
