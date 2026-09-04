import XCTest

@testable import LumiKit

/// Gövdeler `codex app-server` 0.153.2'nin gerçek yanıtından alınmıştır.
final class CodexUsageParserTests: XCTestCase {
    private func responseLine(primary: String, secondary: String) -> Data {
        Data("""
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":\(primary),\
        "secondary":\(secondary),"planType":"plus"}}}
        """.utf8)
    }

    func testMapsPrimaryToSessionAndSecondaryToWeekly() {
        // Arrange: 300 dk = 5 saatlik oturum, 10080 dk = haftalık.
        let data = responseLine(
            primary: #"{"usedPercent":12,"windowDurationMins":300,"resetsAt":1788536879}"#,
            secondary: #"{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1789123679}"#
        )

        // Act
        let snapshot = CodexUsageParser.parse(responseLine: data)

        // Assert
        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 12)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 40)
        XCTAssertEqual(snapshot?.limits.map(\.id), ["session", "week.all"])
        XCTAssertEqual(snapshot?.mode, .subscription)
    }

    func testClassifiesByDurationNotByOrder() {
        // Sunucu pencereleri ters sırada verirse süre kazanır.
        let data = responseLine(
            primary: #"{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1789123679}"#,
            secondary: #"{"usedPercent":12,"windowDurationMins":300,"resetsAt":1788536879}"#
        )

        let snapshot = CodexUsageParser.parse(responseLine: data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 12)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 40)
    }

    func testToleratesOneMinuteWindowDrift() {
        // Eski codex sürümlerinde görülen 299/10079 sapması.
        let data = responseLine(
            primary: #"{"usedPercent":5,"windowDurationMins":299,"resetsAt":1788536879}"#,
            secondary: #"{"usedPercent":9,"windowDurationMins":10079,"resetsAt":1789123679}"#
        )

        let snapshot = CodexUsageParser.parse(responseLine: data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 5)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 9)
    }

    func testUnknownDurationsFallBackToPrimarySecondaryOrder() {
        let data = responseLine(
            primary: #"{"usedPercent":7,"windowDurationMins":42}"#,
            secondary: #"{"usedPercent":8,"windowDurationMins":99}"#
        )

        let snapshot = CodexUsageParser.parse(responseLine: data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 7)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 8)
    }

    func testConvertsUnixSecondsResetToDate() {
        let data = responseLine(
            primary: #"{"usedPercent":1,"windowDurationMins":300,"resetsAt":1788536879}"#,
            secondary: "null"
        )

        let snapshot = CodexUsageParser.parse(responseLine: data)

        XCTAssertEqual(
            snapshot?.fiveHour?.resetsAt,
            Date(timeIntervalSince1970: 1_788_536_879)
        )
        XCTAssertFalse(snapshot?.fiveHour?.resetsRaw.isEmpty ?? true)
    }

    func testMissingResetLeavesRawEmptyButKeepsPercent() {
        let data = responseLine(
            primary: #"{"usedPercent":3,"windowDurationMins":300}"#,
            secondary: "null"
        )

        let snapshot = CodexUsageParser.parse(responseLine: data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 3)
        XCTAssertNil(snapshot?.fiveHour?.resetsAt)
        XCTAssertEqual(snapshot?.fiveHour?.resetsRaw, "")
    }

    func testClampsPercentIntoRange() {
        let data = responseLine(
            primary: #"{"usedPercent":140,"windowDurationMins":300}"#,
            secondary: #"{"usedPercent":-5,"windowDurationMins":10080}"#
        )

        let snapshot = CodexUsageParser.parse(responseLine: data)

        XCTAssertEqual(snapshot?.fiveHour?.percentUsed, 100)
        XCTAssertEqual(snapshot?.weekAll?.percentUsed, 0)
    }

    func testReturnsNilWhenNoWindowIsReadable() {
        let data = responseLine(primary: "null", secondary: "null")

        XCTAssertNil(CodexUsageParser.parse(responseLine: data))
    }

    func testReturnsNilForNonRateLimitResponse() {
        // `initialize` yanıtı yanlışlıkla verilirse snapshot üretilmemeli.
        let data = Data(#"{"id":1,"result":{"codexHome":"/x"}}"#.utf8)

        XCTAssertNil(CodexUsageParser.parse(responseLine: data))
    }

    func testReturnsNilForMalformedJSON() {
        XCTAssertNil(CodexUsageParser.parse(responseLine: Data("not json".utf8)))
    }
}
