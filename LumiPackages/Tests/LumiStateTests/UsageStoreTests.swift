import XCTest
@testable import LumiKit
@testable import LumiState

/// UsageStore davranışı (design/05 §6): tek-yön servis→store, manuel yenileme +
/// min-interval anti-spam, hata son snapshot'ı korur.
@MainActor
final class UsageStoreTests: XCTestCase {
    /// Test'in zaman ekseni — `now` closure'ına enjekte edilir.
    @MainActor final class ClockBox {
        var value: Date
        init(_ value: Date) { self.value = value }
    }

    private func makeSnapshot(percent: Int) -> UsageSnapshot {
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

    func testLoadInitialFetchesExactlyOnce() async {
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 15)))
        let store = UsageStore(service: service)

        await store.loadInitialIfNeeded()
        await store.loadInitialIfNeeded()

        let count = await service.fetchCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.fiveHourPercent, 15)
    }

    func testRefreshBlockedWithinMinIntervalAndAllowedAfter() async {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 10)))
        let store = UsageStore(service: service, now: { clock.value })

        await store.loadInitialIfNeeded()           // t=1000 → fetch #1
        clock.value = Date(timeIntervalSince1970: 1030) // +30sn
        await store.refresh()                        // min-interval içinde → engellenir
        var count = await service.fetchCount
        XCTAssertEqual(count, 1)

        clock.value = Date(timeIntervalSince1970: 1070) // +70sn
        await store.refresh()                        // aralık geçti → fetch #2
        count = await service.fetchCount
        XCTAssertEqual(count, 2)
    }

    func testErrorKeepsPreviousSnapshotAndSurfacesMessage() async {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 22)))
        let store = UsageStore(service: service, now: { clock.value })

        await store.loadInitialIfNeeded()
        XCTAssertEqual(store.fiveHourPercent, 22)
        XCTAssertNil(store.errorMessage)

        await service.setOutcome(.failure(.usageUnavailable(detail: "boom")))
        clock.value = Date(timeIntervalSince1970: 2000)
        await store.refresh()

        XCTAssertEqual(store.fiveHourPercent, 22)    // ekran boşaltılmaz
        XCTAssertNotNil(store.errorMessage)
    }
}
