import XCTest
@testable import LumiMobileKit

final class UsageTests: XCTestCase {
    func testUsageMessageDecodesProvidersAndDeepSeek() {
        let frame = """
        {"v":1,"type":"usage","payload":{
          "providers":[{"id":"claude","limits":[
            {"id":"week.all","label":"Current week","kind":"week","percent":20},
            {"id":"session","label":"Current session","kind":"session","percent":42,"resetsAt":1000000,"durationSec":18000}]},
            {"id":"codex","limits":[],"error":"offline"}],
          "deepseek":{"available":true,"currency":"USD","total":"12.4"}
        }}
        """
        guard case .usage(let report)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("expected .usage")
        }
        XCTAssertEqual(report.providers.map(\.title), ["Claude", "Codex"])
        XCTAssertEqual(report.providers[0].indicatorLimit?.id, "session", "session window wins")
        XCTAssertEqual(report.providers[1].error, "offline")
        XCTAssertNil(report.providers[1].indicatorLimit)
        XCTAssertEqual(report.deepSeek?.balanceLabel, "$12.40")
    }

    func testToneFollowsMacPaceRamp() {
        // 5h window, 2.5h elapsed → 50 pt elapsed.
        let limit = { (percent: Int) in
            UsageLimitReport(id: "s", label: "", kind: "session", percent: percent,
                             resetsAt: 9_000_000, durationSec: 18_000)
        }
        XCTAssertEqual(UsageTone(limit: limit(52), nowMs: 0), .pace(0), "within tolerance → on pace")
        XCTAssertEqual(UsageTone(limit: limit(95), nowMs: 0), .pace(1), "40 pt over → critical")
        XCTAssertEqual(UsageTone(limit: limit(100), nowMs: 0), .pace(1))
        XCTAssertEqual(UsageTone(limit: limit(20), nowMs: 0), .pace(-1), "25+ pt under → ice")
        let noWindow = UsageLimitReport(id: "w", label: "", kind: "week", percent: 60)
        XCTAssertEqual(UsageTone(limit: noWindow, nowMs: 0), .level(60))
        XCTAssertEqual(UsageTone(limit: nil, nowMs: 0), .unknown)
    }

    func testResetLabel() {
        XCTAssertEqual(usageResetLabel(nil, nowMs: 0), nil)
        XCTAssertEqual(usageResetLabel(0, nowMs: 10), "now")
        XCTAssertEqual(usageResetLabel(2 * 3_600_000 + 14 * 60_000, nowMs: 0), "in 2h 14m")
        XCTAssertEqual(usageResetLabel(76 * 3_600_000, nowMs: 0), "in 3d 4h")
    }
}
