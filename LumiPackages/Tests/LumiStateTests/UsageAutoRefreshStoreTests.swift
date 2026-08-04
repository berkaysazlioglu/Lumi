import XCTest
@testable import LumiKit
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
        let store = UsageAutoRefreshStore(usage: usage, activity: activity)
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
        let store = UsageAutoRefreshStore(usage: usage, activity: activity)
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

    func testIntervalClampsInvalidToDefault() {
        XCTAssertEqual(
            UsageAutoRefresh(enabled: true, intervalMinutes: 7).intervalMinutes,
            UsageAutoRefresh.defaults.intervalMinutes
        )
        XCTAssertEqual(
            UsageAutoRefresh(enabled: true, intervalMinutes: 1).intervalMinutes,
            1
        )
    }
}
