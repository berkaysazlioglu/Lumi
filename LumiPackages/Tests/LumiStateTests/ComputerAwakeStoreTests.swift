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
    private var lid: FakeLidSleepControl!
    private var store: ComputerAwakeStore!

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        terminals = TerminalListStore(service: FakeTerminalService(), toasts: toasts)
        settings = SettingsStore(config: FakeConfigService(), toasts: toasts)
        assertion = FakeSleepAssertion()
        lid = FakeLidSleepControl()
        store = ComputerAwakeStore(terminals: terminals, settings: settings, assertion: assertion, lidSleep: lid)
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

    // MARK: - Karar 122: kapak

    func testEnablingLidTakesOwnershipAndQuitRestores() async {
        await store.setLidAwake(true)
        XCTAssertEqual(lid.sleepDisabled, true)
        XCTAssertTrue(store.lidStatus.isOn)
        XCTAssertTrue(store.lidStatus.isOwnedByLumi)

        await store.restoreLidSleep()
        XCTAssertEqual(lid.changes, [true, false])
        XCTAssertEqual(lid.sleepDisabled, false)
        XCTAssertFalse(store.lidStatus.isOwnedByLumi)
    }

    func testCancelledPromptChangesNothing() async {
        lid.nextChange = .cancelled
        await store.setLidAwake(true)
        XCTAssertFalse(store.lidStatus.isOn)
        XCTAssertFalse(store.lidStatus.isOwnedByLumi)
        XCTAssertNil(store.lidStatus.note)
    }

    func testFailureSurfacesMessage() async {
        lid.nextChange = .failed("nope")
        await store.setLidAwake(true)
        XCTAssertEqual(store.lidStatus.note, "nope")
    }

    func testQuitLeavesExternallyEnabledSettingAlone() async {
        lid.sleepDisabled = true
        await store.refreshLidState()
        XCTAssertTrue(store.lidStatus.isOn)
        XCTAssertEqual(store.lidStatus.note, LidAwakeStatus.externalNote)

        await store.restoreLidSleep()
        XCTAssertTrue(lid.changes.isEmpty, "Lumi'nin açmadığı ayara çıkışta dokunulmaz")
    }

    func testLeftoverFromPreviousSessionIsFlaggedOnStart() async throws {
        settings.apply { $0.lidSleepDisabledByLumi = true }
        lid.sleepDisabled = true
        store.start()
        let deadline = Date().addingTimeInterval(2)
        while !store.isLidLeftover, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.lidStatus.note, LidAwakeStatus.leftoverNote)

        await store.setLidAwake(false)
        XCTAssertFalse(store.isLidLeftover)
        XCTAssertFalse(store.lidStatus.isOwnedByLumi)
    }

    func testOwnershipDropsWhenSettingWasRevertedOutsideLumi() async {
        await store.setLidAwake(true)
        lid.sleepDisabled = false
        await store.refreshLidState()
        XCTAssertFalse(store.lidStatus.isOn)
        XCTAssertFalse(store.lidStatus.isOwnedByLumi)
    }

    func testBatteryStateIsReported() async {
        lid.onBattery = true
        await store.refreshLidState()
        XCTAssertTrue(store.lidStatus.isOnBattery)
    }
}
