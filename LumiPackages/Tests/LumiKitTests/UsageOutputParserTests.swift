import XCTest
@testable import LumiKit

/// `claude -p "/usage"` çıktısının parse'ı (design/05 §4). Saf fonksiyon →
/// örnek çıktılarla deterministik test (referans `now` sabitlenir).
final class UsageOutputParserTests: XCTestCase {
    /// Sabit referans: 1 Haz 2026 12:00 UTC — reset yılı buradan türetilir.
    private let now = Date(timeIntervalSince1970: 1_780_660_800)

    private let fullOutput = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 20% used · resets Jun 12 at 1:39pm (Europe/Istanbul)
    Current week (all models): 41% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
    Current week (Sonnet only): 1% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
    """

    func testParsesAllWindowsFromFullOutput() {
        let snapshot = UsageOutputParser.parse(fullOutput, now: now)
        XCTAssertEqual(snapshot.mode, .subscription)
        XCTAssertEqual(snapshot.fiveHour?.percentUsed, 20)
        XCTAssertEqual(snapshot.weekAll?.percentUsed, 41)
        XCTAssertEqual(snapshot.weekSonnet?.percentUsed, 1)
        XCTAssertNil(snapshot.weekOpus)
    }

    func testCapturesRawResetAndTimezone() {
        let snapshot = UsageOutputParser.parse(fullOutput, now: now)
        XCTAssertEqual(snapshot.fiveHour?.resetsRaw, "Jun 12 at 1:39pm")
        XCTAssertEqual(snapshot.fiveHour?.timezone, "Europe/Istanbul")
    }

    func testResolvesResetDateWithCurrentYearAndTimezone() {
        let snapshot = UsageOutputParser.parse(fullOutput, now: now)
        let resetsAt = try? XCTUnwrap(snapshot.fiveHour?.resetsAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: resetsAt!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 13)
        XCTAssertEqual(components.minute, 39)
    }

    func testMissingSonnetLineLeavesItNil() {
        let output = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 5% used · resets Jun 12 at 1:39pm (Europe/Istanbul)
        Current week (all models): 10% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
        """
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.fiveHour?.percentUsed, 5)
        XCTAssertEqual(snapshot.weekAll?.percentUsed, 10)
        XCTAssertNil(snapshot.weekSonnet)
    }

    func testApiKeyModeWithoutPercentLines() {
        let output = "You are currently using an API key to power your Claude Code usage"
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.mode, .apiKey)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertFalse(snapshot.hasAnyWindow)
    }

    func testOpusLineMapsToWeekOpus() {
        let output = "Current week (Opus only): 7% used · resets Jun 14 at 9:00am (Europe/Istanbul)"
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.weekOpus?.percentUsed, 7)
    }

    func testLineWithoutResetStillKeepsPercent() {
        let snapshot = UsageOutputParser.parse("Current session: 42% used", now: now)
        XCTAssertEqual(snapshot.fiveHour?.percentUsed, 42)
        XCTAssertNil(snapshot.fiveHour?.resetsAt)
        XCTAssertEqual(snapshot.fiveHour?.resetsRaw, "")
    }

    func testBrokenLineWithoutPercentOrResetProducesNoWindow() {
        let snapshot = UsageOutputParser.parse("Current session: pending", now: now)
        XCTAssertNil(snapshot.fiveHour)
    }

    func testZeroAndHundredBoundaries() {
        let zero = UsageOutputParser.parse("Current session: 0% used", now: now)
        XCTAssertEqual(zero.fiveHour?.percentUsed, 0)
        let full = UsageOutputParser.parse("Current session: 100% used", now: now)
        XCTAssertEqual(full.fiveHour?.percentUsed, 100)
    }

    func testGarbageInputIsUnknownModeWithNoWindows() {
        let snapshot = UsageOutputParser.parse("totally unrelated text\nno colons here either", now: now)
        XCTAssertEqual(snapshot.mode, .unknown)
        XCTAssertFalse(snapshot.hasAnyWindow)
    }
}
