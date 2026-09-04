import XCTest
@testable import LumiKit
import LumiTestSupport
@testable import LumiState

/// UsageAutoRefreshStore davranışı (karar 20): idle-gate'li tek adım — kullanıcı
/// aktifse tazeler, pasifse atlar. Aralık clamping model katmanında.
@MainActor
final class UsageAutoRefreshStoreTests: XCTestCase {
    private func snapshot(percent: Int) -> UsageSnapshot {
        UsageSnapshot(
            limits: [
                UsageLimit(
                    kind: .session,
                    rawLabel: "Current session",
                    window: UsageWindow(percentUsed: percent, resetsAt: nil, resetsRaw: "", timezone: nil)
                )
            ],
            mode: .subscription,
            fetchedAt: Date()
        )
    }

    func testTickRefreshesWhenUserActive() async {
        // Arrange: idle (10sn) << aralık (5dk = 300sn) → aktif kabul edilir.
        let service = FakeUsageService(outcome: .success(snapshot(percent: 11)))
        let usage = UsageStore(service: service)
        let activity = FakeActivityMonitor(idleSeconds: 10)
        let store = UsageAutoRefreshStore(stores: [usage], activity: activity)
        store.update(UsageAutoRefresh(enabled: true, intervalMinutes: 5))

        // Act
        let didRefresh = await store.performTickIfActive()

        // Assert
        XCTAssertTrue(didRefresh)
        let count = await service.fetchCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(usage.fiveHourPercent, 11)
        store.stop()
    }

    func testTickSkipsWhenUserIdleBeyondInterval() async {
        // Arrange: idle (10000sn) >= aralık (300sn) → pasif → tazelenmez.
        let service = FakeUsageService(outcome: .success(snapshot(percent: 11)))
        let usage = UsageStore(service: service)
        let activity = FakeActivityMonitor(idleSeconds: 10_000)
        let store = UsageAutoRefreshStore(stores: [usage], activity: activity)
        store.update(UsageAutoRefresh(enabled: true, intervalMinutes: 5))

        // Act
        let didRefresh = await store.performTickIfActive()

        // Assert
        XCTAssertFalse(didRefresh)
        let count = await service.fetchCount
        XCTAssertEqual(count, 0)
        XCTAssertNil(usage.fiveHourPercent)
        store.stop()
    }

    // MARK: - Aralık seti (K38-A: {5, 15, 30}, default 5)

    func testAllowedIntervalsMatchTheDesignRecord() {
        XCTAssertEqual(UsageAutoRefresh.allowedIntervals, [5, 15, 30])
        XCTAssertEqual(UsageAutoRefresh.defaults.intervalMinutes, 5)
    }

    func testEveryAllowedIntervalSurvivesValidation() {
        for minutes in UsageAutoRefresh.allowedIntervals {
            XCTAssertEqual(
                UsageAutoRefresh(enabled: true, intervalMinutes: minutes).intervalMinutes,
                minutes
            )
        }
    }

    func testIntervalClampsInvalidToDefault() {
        for invalid in [0, 1, 2, 7, 31, -5] {
            XCTAssertEqual(
                UsageAutoRefresh(enabled: true, intervalMinutes: invalid).intervalMinutes,
                UsageAutoRefresh.defaults.intervalMinutes,
                "\(invalid) izinli set dışında — default'a düşmeli"
            )
        }
    }

    /// TTL cache'i (300 sn) ile hizalanma: en küçük aralık TTL'den KISA olamaz,
    /// yoksa otomatik döngü cache'e takılıp boşa dönerdi (design/05 §cache).
    func testSmallestIntervalIsNotShorterThanTheServiceCacheTTL() {
        XCTAssertEqual(UsageAutoRefresh.allowedIntervals.min(), 5)
    }

    /// Diskteki eski `intervalMinutes: 1` (K38 öncesi set) okumada 5'e clamp'lenir.
    func testLegacyOneMinuteIntervalIsClampedOnRead() {
        XCTAssertEqual(
            UsageAutoRefresh(enabled: true, intervalMinutes: 1),
            UsageAutoRefresh(enabled: true, intervalMinutes: 5)
        )
    }

    /// Clamp gerçekten döngüyü de etkiler: `1` yazılsa bile idle-gate 5 dk'lık
    /// pencereyi kullanır (200 sn boşta olan kullanıcı hâlâ "aktif" sayılır).
    func testLoopUsesClampedIntervalForTheIdleGate() async {
        let service = FakeUsageService(outcome: .success(snapshot(percent: 11)))
        let usage = UsageStore(service: service)
        // 200 sn boşta: 1 dk (60 sn) penceresinde pasif, 5 dk (300 sn) penceresinde aktif.
        let activity = FakeActivityMonitor(idleSeconds: 200)
        let store = UsageAutoRefreshStore(stores: [usage], activity: activity)
        store.update(UsageAutoRefresh(enabled: true, intervalMinutes: 1))

        let didRefresh = await store.performTickIfActive()

        XCTAssertTrue(didRefresh, "aralık 5'e clamp'lendiği için kullanıcı aktif sayılır")
        store.stop()
    }
}
