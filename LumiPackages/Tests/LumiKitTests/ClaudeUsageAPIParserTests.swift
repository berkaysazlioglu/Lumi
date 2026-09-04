import XCTest

@testable import LumiKit

/// Gövdeler `api.anthropic.com/api/oauth/usage`'ın gerçek yanıtından alınmıştır.
final class ClaudeUsageAPIParserTests: XCTestCase {
    private let fullResponse = Data("""
    {
      "five_hour": {"utilization": 57.0, "resets_at": "2026-09-04T12:09:59.578108+00:00"},
      "seven_day": {"utilization": 47.0, "resets_at": "2026-09-05T12:59:59.578129+00:00"},
      "limits": [
        {"kind": "session", "percent": 57, "resets_at": "2026-09-04T12:09:59.578108+00:00",
         "scope": null},
        {"kind": "weekly_all", "percent": 47, "resets_at": "2026-09-05T13:00:00.340586+00:00",
         "scope": null},
        {"kind": "weekly_scoped", "percent": 58, "resets_at": "2026-09-05T13:00:00.340825+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}}}
      ]
    }
    """.utf8)

    func testMapsLimitsArrayPreservingOrder() {
        // Act
        let snapshot = ClaudeUsageAPIParser.parse(fullResponse)

        // Assert — CLI parse'ıyla aynı model, aynı sıra.
        XCTAssertEqual(snapshot?.limits.map(\.id), ["session", "week.all", "week.fable"])
        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 57)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 47)
        XCTAssertEqual(snapshot?.weekly(model: "fable")?.percentUsed, 58)
        XCTAssertEqual(snapshot?.mode, .subscription)
    }

    func testScopedModelLimitCarriesModelNameAndRawLabel() {
        let snapshot = ClaudeUsageAPIParser.parse(fullResponse)

        let scoped = snapshot?.limits.last
        XCTAssertEqual(scoped?.kind, .weeklyModel("Fable"))
        XCTAssertEqual(scoped?.rawLabel, "Current week (Fable)")
    }

    func testParsesISO8601ResetWithFractionalSeconds() {
        let snapshot = ClaudeUsageAPIParser.parse(fullResponse)

        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(
            snapshot?.fiveHour?.resetsAt,
            expected.date(from: "2026-09-04T12:09:59.578108+00:00")
        )
        XCTAssertFalse(snapshot?.fiveHour?.resetsRaw.isEmpty ?? true)
    }

    func testParsesEpochSecondsReset() {
        let data = Data(#"{"limits":[{"kind":"session","percent":10,"resets_at":1788536879}]}"#.utf8)

        let snapshot = ClaudeUsageAPIParser.parse(data)

        XCTAssertEqual(
            snapshot?.fiveHour?.resetsAt,
            Date(timeIntervalSince1970: 1_788_536_879)
        )
    }

    func testFallsBackToTopLevelWindowsWhenLimitsMissing() {
        // Eski/kısaltılmış yanıt biçimi — gösterge boş kalmamalı.
        let data = Data("""
        {"five_hour": {"utilization": 20.0, "resets_at": null},
         "seven_day": {"used_percentage": 33, "resets_at": null}}
        """.utf8)

        let snapshot = ClaudeUsageAPIParser.parse(data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 20)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 33)
    }

    func testUnknownLimitKindIsKeptAsOtherNotDropped() {
        let data = Data(#"{"limits":[{"kind":"brand_new_bucket","percent":5}]}"#.utf8)

        let snapshot = ClaudeUsageAPIParser.parse(data)

        XCTAssertEqual(snapshot?.limits.count, 1)
        XCTAssertEqual(snapshot?.limits.first?.kind, .other)
        XCTAssertEqual(snapshot?.limits.first?.rawLabel, "brand_new_bucket")
    }

    func testScopedLimitWithoutModelNameIsKeptAsOther() {
        let data = Data(#"{"limits":[{"kind":"weekly_scoped","percent":5,"scope":null}]}"#.utf8)

        let snapshot = ClaudeUsageAPIParser.parse(data)

        XCTAssertEqual(snapshot?.limits.first?.kind, .other)
    }

    func testClampsPercentIntoRange() {
        let data = Data("""
        {"limits":[{"kind":"session","percent":180},{"kind":"weekly_all","percent":-4}]}
        """.utf8)

        let snapshot = ClaudeUsageAPIParser.parse(data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 100)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 0)
    }

    func testReturnsNilWhenNothingIsReadable() {
        XCTAssertNil(ClaudeUsageAPIParser.parse(Data(#"{"limits":[]}"#.utf8)))
        XCTAssertNil(ClaudeUsageAPIParser.parse(Data("not json".utf8)))
    }
}
