import XCTest
import LumiKit
@testable import LumiState

/// SessionStarterServicing fake'i — kaydeder, istenirse hata fırlatır.
private actor FakeSessionStarter: SessionStarterServicing {
    private(set) var startedPrompts: [String] = []
    private var errorToThrow: LumiError?

    func setError(_ error: LumiError?) { errorToThrow = error }

    func start(prompt: String) async throws {
        startedPrompts.append(prompt)
        if let errorToThrow { throw errorToThrow }
    }
}

@MainActor
final class SessionScheduleStoreTests: XCTestCase {
    // UTC takvim → DST/yerel-saat belirsizliği olmadan deterministik.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var components = DateComponents()
        components.year = y; components.month = mo; components.day = d
        components.hour = h; components.minute = mi
        return utcCalendar.date(from: components)!
    }

    private func makeStore(now: Date) -> (SessionScheduleStore, FakeSessionStarter) {
        let starter = FakeSessionStarter()
        let store = SessionScheduleStore(
            starter: starter,
            calendar: utcCalendar,
            now: { now }
        )
        return (store, starter)
    }

    // MARK: - nextFireDate (saf)

    func testNextFireDateIsTodayWhenTimeUpcoming() {
        let now = date(2026, 1, 1, 8, 0)
        let next = SessionScheduleStore.nextFireDate(after: now, hour: 9, minute: 0, calendar: utcCalendar)
        XCTAssertEqual(next, date(2026, 1, 1, 9, 0))
    }

    func testNextFireDateRollsToTomorrowWhenTimePassed() {
        let now = date(2026, 1, 1, 10, 0)
        let next = SessionScheduleStore.nextFireDate(after: now, hour: 9, minute: 0, calendar: utcCalendar)
        XCTAssertEqual(next, date(2026, 1, 2, 9, 0))
    }

    // MARK: - fireNow

    func testFireNowCallsStarterWithEffectivePrompt() async {
        let (store, starter) = makeStore(now: date(2026, 1, 1, 8, 0))
        store.update(SessionTrigger(enabled: true, hour: 9, minute: 0, prompt: "kickoff"))

        let fired = await store.fireNow()

        XCTAssertTrue(fired)
        let prompts = await starter.startedPrompts
        XCTAssertEqual(prompts, ["kickoff"])
        XCTAssertEqual(store.lastRun, .success(date(2026, 1, 1, 8, 0)))
    }

    func testFireNowUsesDefaultPromptWhenBlank() async {
        let (store, starter) = makeStore(now: date(2026, 1, 1, 8, 0))
        store.update(SessionTrigger(enabled: true, hour: 9, minute: 0, prompt: "   "))

        await store.fireNow()

        let prompts = await starter.startedPrompts
        XCTAssertEqual(prompts, ["hello"])
    }

    func testFireNowRecordsFailure() async {
        let (store, starter) = makeStore(now: date(2026, 1, 1, 8, 0))
        await starter.setError(.cliNotFound(binary: "claude"))
        store.update(SessionTrigger(enabled: true, hour: 9, minute: 0, prompt: "hello"))

        let fired = await store.fireNow()

        XCTAssertFalse(fired)
        if case .failure(let detail, let at) = store.lastRun {
            XCTAssertTrue(detail.contains("claude"))
            XCTAssertEqual(at, date(2026, 1, 1, 8, 0))
        } else {
            XCTFail("expected failure, got \(String(describing: store.lastRun))")
        }
    }

    // MARK: - update / nextFireDate yan etkisi

    func testUpdateEnabledComputesNextFireDate() {
        let (store, _) = makeStore(now: date(2026, 1, 1, 8, 0))
        store.update(SessionTrigger(enabled: true, hour: 9, minute: 0, prompt: "hello"))
        XCTAssertEqual(store.nextFireDate, date(2026, 1, 1, 9, 0))
        store.stop()
    }

    func testUpdateDisabledClearsNextFireDate() {
        let (store, _) = makeStore(now: date(2026, 1, 1, 8, 0))
        store.update(SessionTrigger(enabled: true, hour: 9, minute: 0, prompt: "hello"))
        store.update(SessionTrigger(enabled: false, hour: 9, minute: 0, prompt: "hello"))
        XCTAssertNil(store.nextFireDate)
    }
}
