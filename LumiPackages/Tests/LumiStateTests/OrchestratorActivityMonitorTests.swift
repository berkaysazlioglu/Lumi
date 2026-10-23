import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 123 Faz 2: monitör haiku özetlerinin toplandığı feed'i dinler ve
/// yeni özeti `codex queue` ile çalışan orchestrator'a bırakır.
@MainActor
final class OrchestratorActivityMonitorTests: XCTestCase {
    private var feed: OrchestratorActivityFeed!
    private var launcher: FakeOrchestratorLauncher!
    private var target: OrchestratorDeliveryTarget?
    private var monitor: OrchestratorActivityMonitor!

    private let now = Date(timeIntervalSince1970: 10_000)

    override func setUp() async throws {
        feed = OrchestratorActivityFeed()
        launcher = FakeOrchestratorLauncher()
        target = OrchestratorDeliveryTarget(thread: "thread-1", codexHome: "/h")
        monitor = OrchestratorActivityMonitor(
            feed: feed, launcher: launcher, target: { [unowned self] in self.target },
            batchDelay: .milliseconds(30), now: { [unowned self] in self.now }
        )
        monitor.start()
    }

    private func event(_ summary: String, terminal: TerminalID = TerminalID(), title: String = "api") -> OrchestratorEvent {
        OrchestratorEvent(terminalID: terminal, terminalTitle: title, location: "api · main",
                          kind: .finished, summary: summary, needsUser: false, at: now)
    }

    /// Toplama beklemesi + teslim.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    func testNewSummaryIsQueuedToTheOrchestratorWithoutUserInput() async throws {
        feed.append(event("Testler yeşil."))
        await settle()

        let queued = try XCTUnwrap(launcher.queued.first)
        XCTAssertEqual(queued.thread, "thread-1")
        XCTAssertEqual(queued.codexHome, "/h")
        XCTAssertTrue(queued.message.hasPrefix(OrchestratorPrompt.activityOpen))
        XCTAssertTrue(queued.message.contains("Testler yeşil."))
        XCTAssertFalse(feed.hasUnreported)
    }

    func testSimultaneousSummariesAreBatchedIntoOneNote() async {
        feed.append(event("a bitti", title: "a"))
        feed.append(event("b bitti", title: "b"))
        await settle()

        XCTAssertEqual(launcher.queued.count, 1)
        XCTAssertTrue(launcher.queued[0].message.contains("a bitti"))
        XCTAssertTrue(launcher.queued[0].message.contains("b bitti"))
    }

    func testWithoutATargetSummariesWaitUntilCodexReportsItsThread() async {
        target = nil
        feed.append(event("bekleyen"))
        await settle()
        XCTAssertTrue(launcher.queued.isEmpty)
        XCTAssertTrue(feed.hasUnreported, "kaybolmaz, bekler")

        target = OrchestratorDeliveryTarget(thread: "thread-2", codexHome: nil)
        monitor.targetBecameAvailable()
        await settle()

        XCTAssertEqual(launcher.queued.map(\.thread), ["thread-2"])
        XCTAssertTrue(launcher.queued[0].message.contains("bekleyen"))
    }

    func testFailedDeliveryKeepsTheSummaryForTheNextAttempt() async {
        launcher.failQueue(with: .orchestratorQueueFailed(detail: "unknown thread"))
        feed.append(event("ilk"))
        await settle()
        XCTAssertTrue(launcher.queued.isEmpty)
        XCTAssertNotNil(monitor.lastError)
        XCTAssertTrue(feed.hasUnreported)

        launcher.failQueue(with: nil)
        feed.append(event("ikinci"))
        await settle()

        XCTAssertEqual(launcher.queued.count, 1)
        XCTAssertTrue(launcher.queued[0].message.contains("ilk"))
        XCTAssertTrue(launcher.queued[0].message.contains("ikinci"))
        XCTAssertNil(monitor.lastError)
    }

    func testStoppedMonitorDoesNotDeliver() async {
        monitor.stop()
        feed.append(event("x"))
        await settle()
        XCTAssertTrue(launcher.queued.isEmpty)
    }
}
