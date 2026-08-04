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
        XCTAssertEqual(snapshot.weekly(model: "Sonnet")?.percentUsed, 1)
        XCTAssertNil(snapshot.weekly(model: "Opus"))
    }

    func testLimitsKeepCliOrderAndTitles() {
        let snapshot = UsageOutputParser.parse(fullOutput, now: now)
        XCTAssertEqual(
            snapshot.limits.map(\.title),
            ["5-hour session", "Weekly (all models)", "Weekly (Sonnet)"]
        )
    }

    /// Regresyon: model-özel haftalık satır, haftalık TOPLAMI ezmemeli
    /// (eski parser "Current week (Fable)" satırını `weekAll` sanıyordu).
    func testModelWeeklyLineDoesNotOverwriteWeeklyTotal() {
        let output = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 0% used · resets Jul 27 at 7:59pm (Europe/Istanbul)
        Current week (all models): 7% used · resets Aug 1 at 3:59pm (Europe/Istanbul)
        Current week (Fable): 2% used · resets Aug 1 at 3:59pm (Europe/Istanbul)
        """
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.weekAll?.percentUsed, 7)
        XCTAssertEqual(snapshot.weekly(model: "Fable")?.percentUsed, 2)
        XCTAssertEqual(snapshot.limits.count, 3)
    }

    /// Model limiti kaldırılırsa (3 yerine 2 satır) hata değil — kalanlar durur.
    func testFewerLimitsAreParsedWithoutError() {
        let output = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 5% used · resets Jun 12 at 1:39pm (Europe/Istanbul)
        Current week (all models): 10% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
        """
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.fiveHour?.percentUsed, 5)
        XCTAssertEqual(snapshot.weekAll?.percentUsed, 10)
        XCTAssertNil(snapshot.weekly(model: "Sonnet"))
        XCTAssertTrue(snapshot.hasAnyWindow)
    }

    /// İleride yeni bir model limiti eklenirse kod değişmeden listeye girer.
    func testUnknownModelWeeklyLineIsKeptAsModelLimit() {
        let output = """
        Current week (all models): 12% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
        Current week (Somethingnew): 3% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
        """
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.limits.last?.kind, .weeklyModel("Somethingnew"))
        XCTAssertEqual(snapshot.limits.last?.title, "Weekly (Somethingnew)")
    }

    /// "What's contributing" bölümü limit değildir — listeye sızmamalı.
    func testContributingSectionLinesAreIgnored() {
        let output = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 0% used · resets Jul 27 at 7:59pm (Europe/Istanbul)
        Current week (all models): 7% used · resets Aug 1 at 3:59pm (Europe/Istanbul)

        What's contributing to your limits usage?

        Last 24h · 684 requests · 11 sessions
          71% of your usage was at >150k context
          Top MCP servers: UnityMCP 36%
          Top skills: /unity-mcp-skill 2%
          Top subagents: deep-reasoner 3%, Explore 1%
        """
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.limits.map(\.kind), [.session, .weeklyAll])
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

    func testApiKeyModeWithoutPercentLines() {
        let output = "You are currently using an API key to power your Claude Code usage"
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.mode, .apiKey)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertFalse(snapshot.hasAnyWindow)
    }

    func testOpusLineMapsToOpusWeeklyLimit() {
        let output = "Current week (Opus only): 7% used · resets Jun 14 at 9:00am (Europe/Istanbul)"
        let snapshot = UsageOutputParser.parse(output, now: now)
        XCTAssertEqual(snapshot.weekly(model: "Opus")?.percentUsed, 7)
        XCTAssertEqual(snapshot.limits.first?.title, "Weekly (Opus)")
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
