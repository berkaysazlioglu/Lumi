import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

/// Refactor 3.11: TTL dekoratörü. **Composition root'a bağlı DEĞİL** — K38
/// kararı verilene kadar yalnız burada yaşar.
final class CachingUsageServiceTests: XCTestCase {
    private func snapshot(percent: Int) -> UsageSnapshot {
        UsageSnapshot(
            limits: [
                UsageLimit(
                    kind: .session,
                    rawLabel: "Current session",
                    window: UsageWindow(
                        percentUsed: percent, resetsAt: nil, resetsRaw: "", timezone: nil
                    )
                ),
            ],
            mode: .subscription,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeCache(
        _ inner: FakeUsageService,
        ttl: Duration = .seconds(300),
        clock: ManualClock
    ) -> CachingUsageService<ManualClock> {
        CachingUsageService(wrapping: inner, ttl: ttl, clock: clock)
    }

    func testSecondFetchWithinTTLDoesNotHitWrappedService() async throws {
        let inner = FakeUsageService(outcome: .success(snapshot(percent: 10)))
        let clock = ManualClock()
        let cache = makeCache(inner, clock: clock)

        _ = try await cache.fetch()
        clock.advance(by: .seconds(299))
        let second = try await cache.fetch()

        let count = await inner.fetchCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(second.fiveHour?.percentUsed, 10)
    }

    func testFetchAfterTTLRefetches() async throws {
        let inner = FakeUsageService(outcome: .success(snapshot(percent: 10)))
        let clock = ManualClock()
        let cache = makeCache(inner, clock: clock)

        _ = try await cache.fetch()
        await inner.setOutcome(.success(snapshot(percent: 55)))
        clock.advance(by: .seconds(300))
        let second = try await cache.fetch()

        let count = await inner.fetchCount
        XCTAssertEqual(count, 2)
        XCTAssertEqual(second.fiveHour?.percentUsed, 55)
    }

    func testErrorIsNotCachedAndPropagates() async {
        let inner = FakeUsageService(outcome: .failure(.usageUnavailable(detail: "boom")))
        let clock = ManualClock()
        let cache = makeCache(inner, clock: clock)

        for _ in 0 ..< 2 {
            do {
                _ = try await cache.fetch()
                XCTFail("hata bekleniyordu")
            } catch let error as LumiError {
                XCTAssertEqual(error, .usageUnavailable(detail: "boom"))
            } catch {
                XCTFail("beklenmeyen hata: \(error)")
            }
        }
        // Hata cache'lenmez: ikinci çağrı da servise gider.
        let count = await inner.fetchCount
        XCTAssertEqual(count, 2)
    }

    func testFreshCacheSurvivesATransientErrorAfterIt() async throws {
        let inner = FakeUsageService(outcome: .success(snapshot(percent: 42)))
        let clock = ManualClock()
        let cache = makeCache(inner, clock: clock)

        _ = try await cache.fetch()
        await inner.setOutcome(.failure(.usageUnavailable(detail: "5xx")))
        clock.advance(by: .seconds(100))

        // TTL içinde: servise hiç gidilmez, cache döner.
        let cachedSnapshot = try await cache.fetch()
        XCTAssertEqual(cachedSnapshot.fiveHour?.percentUsed, 42)
        let count = await inner.fetchCount
        XCTAssertEqual(count, 1)
    }

    func testInvalidateForcesRefetchWithinTTL() async throws {
        let inner = FakeUsageService(outcome: .success(snapshot(percent: 1)))
        let clock = ManualClock()
        let cache = makeCache(inner, clock: clock)

        _ = try await cache.fetch()
        await cache.invalidate()
        _ = try await cache.fetch()

        let count = await inner.fetchCount
        XCTAssertEqual(count, 2)
    }

    func testProviderIsForwardedFromWrappedService() async {
        let inner = FakeUsageService(provider: .codex, outcome: .success(snapshot(percent: 0)))
        let cache = makeCache(inner, clock: ManualClock())

        XCTAssertEqual(cache.provider, .codex)
    }
}
