import Foundation
import XCTest
@testable import LumiTerminal

/// Karar 116: hover'daki yol varlığı önbelleği.
@MainActor
final class TerminalLinkPathCacheTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1000)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { value += 1; return value } }
        var count: Int { lock.withLock { value } }
    }

    func testAnswersAreCachedThenExpire() {
        let clock = Clock()
        let probes = Counter()
        let cache = TerminalLinkPathCache(
            probe: { _ in probes.next() > 0 }, runsInline: true, now: { clock.now }
        )
        var completions = 0

        cache.request(["/a"]) { completions += 1 }
        cache.request(["/a"]) { completions += 1 }
        XCTAssertEqual(cache.exists("/a"), true)
        XCTAssertEqual(probes.count, 1, "taze cevap yeniden sorulmaz")
        XCTAssertEqual(completions, 1)

        // Az önce oluşturulan dosya bir süre sonra link olabilmeli.
        clock.now += TerminalLinkPathCache.entryLifetime + 1
        XCTAssertNil(cache.exists("/a"))
        cache.request(["/a"]) {}
        XCTAssertEqual(probes.count, 2)
    }

    /// Sorgu ana thread'i bloklamaz; cevap ana thread'de gelir.
    func testBackgroundProbeDeliversOnMain() async {
        let cache = TerminalLinkPathCache(probe: { _ in
            XCTAssertFalse(Thread.isMainThread)
            return false
        })
        await withCheckedContinuation { continuation in
            cache.request(["/missing"]) {
                XCTAssertTrue(Thread.isMainThread)
                continuation.resume()
            }
        }
        XCTAssertEqual(cache.exists("/missing"), false)
    }
}
