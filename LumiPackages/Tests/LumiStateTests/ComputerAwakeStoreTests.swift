import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 43: mod + çalışan ajan sayısı → uyku engeli.
@MainActor
final class ComputerAwakeStoreTests: XCTestCase {
    private var terminals: TerminalListStore!
    private var settings: SettingsStore!
    private var assertion: FakeSleepAssertion!
    private var store: ComputerAwakeStore!

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        terminals = TerminalListStore(service: FakeTerminalService(), toasts: toasts)
        settings = SettingsStore(config: FakeConfigService(), toasts: toasts)
        assertion = FakeSleepAssertion()
        store = ComputerAwakeStore(terminals: terminals, settings: settings, assertion: assertion)
    }

    override func tearDown() async throws {
        store.stop()
    }

    private func spawn(_ status: TerminalStatus) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/r", createdAt: .now, status: .idle)
        terminals.apply(.spawned(meta))
        terminals.apply(.statusChanged(meta.id, status))
        return meta
    }

    func testOffNeverAssertsEvenWithWorkingAgents() {
        _ = spawn(.working)
        store.sync()
        XCTAssertFalse(assertion.isPreventingSleep)
        XCTAssertEqual(store.status, ComputerAwakeStatus(mode: .off, isActive: false))
    }

    func testOnAssertsWithoutAgents() {
        store.setMode(.on)
        store.sync()
        XCTAssertTrue(assertion.isPreventingSleep)
        XCTAssertEqual(store.status.text, "On · Active")
    }

    func testAgentModeFollowsWorkingTerminals() {
        store.setMode(.auto)
        store.sync()
        XCTAssertFalse(assertion.isPreventingSleep)

        let meta = spawn(.working)
        store.sync()
        XCTAssertTrue(assertion.isPreventingSleep)
        XCTAssertEqual(store.workingAgentCount, 1)

        terminals.apply(.statusChanged(meta.id, .waitingUnseen))
        store.sync()
        XCTAssertFalse(assertion.isPreventingSleep, "turn bitince engel kalkar")
    }

    func testStartObservesChangesAndStopReleases() async throws {
        store.setMode(.auto)
        store.start()
        XCTAssertFalse(assertion.isPreventingSleep)

        _ = spawn(.working)
        let deadline = Date().addingTimeInterval(2)
        while !assertion.isPreventingSleep, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(assertion.isPreventingSleep, "gözlem döngüsü değişimi yakalar")

        store.stop()
        XCTAssertFalse(assertion.isPreventingSleep, "stop assertion'ı bırakır")
    }

    func testFailedAssertionShowsInactive() {
        assertion.shouldFail = true
        store.setMode(.on)
        store.sync()
        XCTAssertTrue(store.assertionFailed)
        XCTAssertFalse(store.status.isActive)
    }
}
