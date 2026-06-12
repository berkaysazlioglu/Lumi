import Foundation
import XCTest
import LumiKit
@testable import LumiServices

@MainActor
private final class FakeScheduler: RepeatingScheduling {
    private(set) var scheduled: [String: (interval: TimeInterval, tick: @MainActor () -> Void)] = [:]
    private(set) var cancelCalls: [String] = []

    var activeIDs: Set<String> { Set(scheduled.keys) }

    func schedule(id: String, interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) {
        scheduled[id] = (interval, tick)
    }

    func cancel(id: String) {
        cancelCalls.append(id)
        scheduled.removeValue(forKey: id)
    }

    func fire(id: String) {
        scheduled[id]?.tick()
    }
}

private final class FakePresenter: NotificationPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var presentedRecords: [(id: String, title: String, body: String)] = []
    private var removedRecords: [String] = []

    func requestAuthorization() async -> Bool { true }

    @MainActor
    func present(id: String, title: String, body: String) {
        lock.lock()
        presentedRecords.append((id, title, body))
        lock.unlock()
    }

    @MainActor
    func removeDelivered(id: String) {
        lock.lock()
        removedRecords.append(id)
        lock.unlock()
    }

    var presented: [(id: String, title: String, body: String)] {
        lock.lock()
        defer { lock.unlock() }
        return presentedRecords
    }

    var removed: [String] {
        lock.lock()
        defer { lock.unlock() }
        return removedRecords
    }
}

/// spec/13 §4 tablosunun birebir testleri — Faz 3 çıkış kriterleri
/// (interval-sızıntı testi dahil).
@MainActor
final class NotificationServiceTests: XCTestCase {
    private var presenter: FakePresenter!
    private var scheduler: FakeScheduler!
    private var service: NotificationService!
    private let terminalID = TerminalID()

    override func setUp() async throws {
        presenter = FakePresenter()
        scheduler = FakeScheduler()
        service = NotificationService(presenter: presenter, scheduler: scheduler)
        service.setWindowFocused(false) // bildirimlerin görünür olduğu durum
    }

    func testWaitingUnseenNotifiesImmediatelyAndSchedulesRepeat() {
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)

        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertEqual(presenter.presented.first?.body, NotificationService.waitingBody)
        XCTAssertEqual(scheduler.scheduled[terminalID.description]?.interval, 60) // 1 dk default

        scheduler.fire(id: terminalID.description)
        XCTAssertEqual(presenter.presented.count, 2, "interval tick yeniden bildirmeli")
    }

    func testWaitingSeenOnlySchedulesNoImmediate() {
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingSeen)

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertEqual(scheduler.scheduled[terminalID.description]?.interval, 300) // 5 dk default
    }

    func testFocusedAndWorkingClearInterval() {
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        XCTAssertFalse(scheduler.activeIDs.isEmpty)

        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingFocused)
        XCTAssertTrue(scheduler.activeIDs.isEmpty)

        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .working)
        XCTAssertTrue(scheduler.activeIDs.isEmpty)
    }

    func testErrorIsOneShot() {
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .error)
        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertEqual(presenter.presented.first?.body, NotificationService.errorBody)
        XCTAssertTrue(scheduler.activeIDs.isEmpty, "error tekrar bildirimi planlamaz")
    }

    func testWindowFocusGuardSuppressesNativeNotification() async {
        service.setWindowFocused(true)
        let stream = service.events()

        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        XCTAssertTrue(presenter.presented.isEmpty, "pencere odaklıyken OS bildirimi yok")

        // Bell sinyali (ayar açıkken) odaktan bağımsız gider
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event, .bell(terminalID, repoName: "lumi"))
    }

    /// Faz 3 çıkış kriteri: interval-sızıntı testi (spec/13 §4 cleanup sözleşmesi).
    func testTerminalRemovedCancelsIntervalAndCleansDelivered() {
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        XCTAssertEqual(scheduler.activeIDs, [terminalID.description])

        service.terminalRemoved(terminalID)
        XCTAssertTrue(scheduler.activeIDs.isEmpty, "interval timer sızdı!")
        XCTAssertEqual(presenter.removed, [terminalID.description])
    }

    func testTransitionReplacesInterval() {
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingSeen)

        XCTAssertEqual(scheduler.activeIDs.count, 1, "terminal başına en fazla bir interval")
        XCTAssertEqual(scheduler.scheduled[terminalID.description]?.interval, 300)
    }

    func testDisabledSettingsSkipNotificationAndBell() async {
        service.updateSettings(NotificationSettings(
            unseenEnabled: false,
            unseenIntervalMinutes: 1,
            seenEnabled: false,
            seenIntervalMinutes: 5
        ))
        let stream = service.events()

        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(scheduler.activeIDs.isEmpty)

        // Karar 17: kapalıyken waiting bell'i de gönderilmez. Stream'de "event yok"
        // doğrudan assert edilemez; ayardan bağımsız giden error bell'ini sentinel
        // olarak itip İLK event'in o olduğunu doğruluyoruz.
        let sentinelID = TerminalID()
        service.handleStatusChange(id: sentinelID, repoName: "sentinel", status: .error)
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event, .bell(sentinelID, repoName: "sentinel"))
    }

    func testCustomIntervalsRespected() {
        service.updateSettings(NotificationSettings(
            unseenEnabled: true,
            unseenIntervalMinutes: 3,
            seenEnabled: true,
            seenIntervalMinutes: 10
        ))
        service.handleStatusChange(id: terminalID, repoName: "lumi", status: .waitingUnseen)
        XCTAssertEqual(scheduler.scheduled[terminalID.description]?.interval, 180)
    }
}
