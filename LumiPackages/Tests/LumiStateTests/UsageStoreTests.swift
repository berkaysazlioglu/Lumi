import XCTest
@testable import LumiKit
import LumiTestSupport
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

// MARK: - Açık/kapalı kapısı (karar 32)

extension UsageStoreTests {
    func testDisabledStoreMakesNoRequestAtAll() async {
        // Kapalı sağlayıcı için HİÇBİR istek atılmamalı — ne ilk yükleme ne manuel.
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 15)))
        let store = UsageStore(service: service)
        store.setEnabled(false)

        await store.loadInitialIfNeeded()
        await store.refresh()

        let count = await service.fetchCount
        XCTAssertEqual(count, 0)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.canRefresh)
    }

    func testReEnablingLoadsAgainSoIndicatorIsNotBlank() async {
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 15)))
        let store = UsageStore(service: service)

        await store.loadInitialIfNeeded()
        store.setEnabled(false)
        store.setEnabled(true)
        await store.loadInitialIfNeeded()

        let count = await service.fetchCount
        XCTAssertEqual(count, 2)
    }

    func testProviderIsTakenFromService() {
        let store = UsageStore(
            service: FakeUsageService(provider: .codex, outcome: .success(makeSnapshot(percent: 1)))
        )

        XCTAssertEqual(store.provider, .codex)
    }

    // MARK: - minRefreshInterval kapısı (2.8 tamamlayıcıları)

    func testCanRefreshIsTrueBeforeAnyAttempt() {
        let store = UsageStore(service: FakeUsageService(outcome: .success(makeSnapshot(percent: 1))))
        XCTAssertTrue(store.canRefresh, "hiç denenmemişken kapı açık")
    }

    func testIntervalBoundaryIsInclusive() async {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 10)))
        let store = UsageStore(service: service, now: { clock.value })

        await store.loadInitialIfNeeded()
        clock.value = Date(timeIntervalSince1970: 1000 + UsageStore.minRefreshInterval - 0.001)
        XCTAssertFalse(store.canRefresh, "aralık dolmadan bir tık önce kapalı")

        clock.value = Date(timeIntervalSince1970: 1000 + UsageStore.minRefreshInterval)
        XCTAssertTrue(store.canRefresh, "tam aralıkta (>=) açık")
        await store.refresh()
        let count = await service.fetchCount
        XCTAssertEqual(count, 2)
    }

    /// Kapı BAŞARISIZ denemede de kurulur — hata döngüsünde spam olmaz.
    func testFailedAttemptAlsoArmsTheGate() async {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        let service = FakeUsageService(outcome: .failure(.usageUnavailable(detail: "offline")))
        let store = UsageStore(service: service, now: { clock.value })

        await store.loadInitialIfNeeded()
        XCTAssertFalse(store.canRefresh)

        clock.value = Date(timeIntervalSince1970: 1010)
        await store.refresh()
        let count = await service.fetchCount
        XCTAssertEqual(count, 1, "hata sonrası da min aralık beklenir")
    }

    /// Kapalı gösterge hiç istek atmaz — min aralık dolmuş olsa bile (karar 32).
    func testDisabledStoreIgnoresTheGateEntirely() async {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        let service = FakeUsageService(outcome: .success(makeSnapshot(percent: 10)))
        let store = UsageStore(service: service, now: { clock.value })

        store.setEnabled(false)
        clock.value = Date(timeIntervalSince1970: 9999)
        XCTAssertFalse(store.canRefresh)
        await store.refresh()

        let count = await service.fetchCount
        XCTAssertEqual(count, 0)
    }
}
