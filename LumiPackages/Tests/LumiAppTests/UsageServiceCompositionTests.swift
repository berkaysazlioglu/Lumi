import Foundation
import XCTest
import LumiKit
@testable import LumiAppCore

/// K38-A: üretim grafiğinde her kullanım servisi TTL cache dekoratörüyle
/// sarılır (design/05 §cache "≥5 dk TTL"). Somut dekoratör tipini isimlemek
/// yerine yeteneğine bakılır — dekoratör değişse de sözleşme aynı kalır.
@MainActor
final class UsageServiceCompositionTests: XCTestCase {
    func testEveryProviderGetsACacheDecoratedUsageService() {
        let registry = LiveServiceRegistry(mode: .development)

        for provider in AgentProvider.allCases {
            let service = registry.usage(for: provider)
            XCTAssertEqual(service.provider, provider)
            XCTAssertTrue(
                service is any UsageCacheInvalidating,
                "\(provider.rawValue) servisi TTL cache ile sarılmamış (K38-A)"
            )
        }
    }

    func testCacheTTLMatchesTheDesignRecord() {
        XCTAssertEqual(LiveServiceRegistry.usageCacheTTL, .seconds(300))
    }

    /// TTL, en küçük otomatik tazeleme aralığından uzun OLMAMALI; olsaydı
    /// otomatik döngü cache'e takılıp hiç tazelenmezdi.
    func testCacheTTLIsNotLongerThanTheSmallestAutoRefreshInterval() throws {
        let smallest = try XCTUnwrap(UsageAutoRefresh.allowedIntervals.min())
        XCTAssertLessThanOrEqual(
            LiveServiceRegistry.usageCacheTTL,
            .seconds(smallest * 60)
        )
    }
}
