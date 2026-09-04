import Foundation
import XCTest
import LumiKit
import LumiState
import LumiTestSupport
@testable import LumiAppCore

/// `ConfigSideEffectCoordinator`'ın diff kuralları (design/02 §2, karar 11).
///
/// Karakterizasyon kalkanı: her kural için (a) YALNIZ ilgili callback tetiklenir,
/// (b) "falsy" değerler (0, "", false, boş dizi) de propagate edilir — Electron'un
/// truthiness bug'ı (karar 11) geri gelemez.
@MainActor
final class ConfigSideEffectCoordinatorTests: XCTestCase {
    /// Tetiklenen tüm yan etkilerin tek kaydı — "yalnız bu tetiklendi" iddiası
    /// için karşılaştırılabilir bir küme gerekir.
    private struct Recorder {
        var fontSizes: [Int] = []
        var fontFamilyCalls = 0
        var cursors: [(shape: TerminalCursorShape, blink: Bool)] = []
        var autoMinimize: [Bool] = []
        var sessionTriggers: [SessionTrigger] = []
        var usageAutoRefresh: [UsageAutoRefresh] = []
        var usageIndicators: [UsageIndicators] = []

        /// Hangi callback'lerin hiç çalıştığı — sıralı, karşılaştırılabilir.
        var firedKinds: Set<String> {
            var kinds: Set<String> = []
            if !fontSizes.isEmpty { kinds.insert("fontSize") }
            if fontFamilyCalls > 0 { kinds.insert("fontFamily") }
            if !cursors.isEmpty { kinds.insert("cursor") }
            if !autoMinimize.isEmpty { kinds.insert("autoMinimize") }
            if !sessionTriggers.isEmpty { kinds.insert("sessionTrigger") }
            if !usageAutoRefresh.isEmpty { kinds.insert("usageAutoRefresh") }
            if !usageIndicators.isEmpty { kinds.insert("usageIndicators") }
            return kinds
        }
    }

    private final class Box: @unchecked Sendable {
        var recorder = Recorder()
    }

    private struct Harness {
        let coordinator: ConfigSideEffectCoordinator
        let config: FakeConfigService
        let repo: FakeRepoService
        let repoStore: RepoStore
        let notifications: FakeNotificationService
        let box: Box
    }

    /// `start()` sonrası tüketici Task'ı `events()` çağırana kadar beklenir:
    /// abonelikten ÖNCE gönderilen event düşer (plan 5.6 — boot penceresi).
    private func makeHarness() async -> Harness {
        let config = FakeConfigService()
        let repo = FakeRepoService()
        let repoStore = RepoStore(service: repo)
        let notifications = FakeNotificationService()
        let coordinator = ConfigSideEffectCoordinator(
            config: config,
            repo: repo,
            repoStore: repoStore,
            notifications: notifications
        )
        let box = Box()
        coordinator.onTerminalFontSizeChanged = { box.recorder.fontSizes.append($0) }
        coordinator.onTerminalFontFamilyChanged = { box.recorder.fontFamilyCalls += 1 }
        coordinator.onTerminalCursorChanged = { box.recorder.cursors.append(($0, $1)) }
        coordinator.onAutoMinimizeOnSendChanged = { box.recorder.autoMinimize.append($0) }
        coordinator.onSessionTriggerChanged = { box.recorder.sessionTriggers.append($0) }
        coordinator.onUsageAutoRefreshChanged = { box.recorder.usageAutoRefresh.append($0) }
        coordinator.onUsageIndicatorsChanged = { box.recorder.usageIndicators.append($0) }
        coordinator.start()
        await waitUntil("koordinatör config event'lerine abone olmadı") {
            config.subscriberCount > 0
        }
        return Harness(
            coordinator: coordinator,
            config: config,
            repo: repo,
            repoStore: repoStore,
            notifications: notifications,
            box: box
        )
    }

    /// `old` her testte aynı taban; `new` yalnız test edilen alanda farklıdır.
    private func emit(
        _ harness: Harness,
        from old: AppConfig = .defaults,
        _ mutate: (inout AppConfig) -> Void
    ) {
        var new = old
        mutate(&new)
        harness.config.emitConfigChange(old: old, new: new)
    }

    // MARK: - 1. projectsRoot / additionalPaths → repo servisi + repoStore

    func testProjectsRootChangePropagatesRootsToRepoService() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.projectsRoot = "/tmp/projects" }

        let calls = await pollSetRoots(harness)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.projectsRoot, "/tmp/projects")
        XCTAssertEqual(harness.box.recorder.firedKinds, [], "başka callback tetiklenmemeli")
    }

    /// Karar 11: projectsRoot BOŞ STRING'e düşse de yan etki atlanmaz.
    func testEmptyProjectsRootStillPropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        var old = AppConfig.defaults
        old.projectsRoot = "/tmp/projects"

        emit(harness, from: old) { $0.projectsRoot = "" }

        let calls = await pollSetRoots(harness)
        XCTAssertEqual(calls.first?.projectsRoot, "", "boş string de propagate edilir")
    }

    func testAdditionalPathsChangeUpdatesRepoStore() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        let path = AdditionalPath(id: "a", path: "/tmp/extra", type: .root, label: "Extra")

        emit(harness) { $0.additionalPaths = [path] }

        await waitUntil("repoStore.additionalPaths güncellenmedi") {
            harness.repoStore.additionalPaths == [path]
        }
        let calls = await pollSetRoots(harness)
        XCTAssertEqual(calls.first?.additionalPaths, [path])
    }

    /// Karar 11: dolu listeden BOŞ listeye geçiş de bir değişimdir.
    func testEmptyingAdditionalPathsStillPropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        var old = AppConfig.defaults
        old.additionalPaths = [AdditionalPath(id: "a", path: "/tmp/extra", type: .root)]

        emit(harness, from: old) { $0.additionalPaths = [] }

        let calls = await pollSetRoots(harness)
        XCTAssertEqual(calls.first?.additionalPaths, [])
        XCTAssertEqual(harness.repoStore.additionalPaths, [])
    }

    // MARK: - 2. notifications → NotificationServicing

    func testNotificationSettingsChangePropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        var settings = NotificationSettings.defaults
        settings.unseenEnabled.toggle()

        emit(harness) { $0.notifications = settings }

        await waitUntil("bildirim ayarı iletilmedi") {
            harness.notifications.settingsUpdates == [settings]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, [])
    }

    // MARK: - 3. terminalFontSize

    func testFontSizeChangeFiresOnlyFontSizeCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.terminalFontSize = 18 }

        await waitUntil("font boyutu callback'i çalışmadı") {
            harness.box.recorder.fontSizes == [18]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["fontSize"])
    }

    /// Karar 11: 0 "falsy"dir ama yine de bir değişimdir.
    func testZeroFontSizePropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.terminalFontSize = 0 }

        await waitUntil("0 font boyutu atlandı") {
            harness.box.recorder.fontSizes == [0]
        }
    }

    // MARK: - 4. terminalFontFamily

    func testFontFamilyChangeFiresOnlyFamilyCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.terminalFontFamily = "Menlo" }

        await waitUntil("font ailesi callback'i çalışmadı") {
            harness.box.recorder.fontFamilyCalls == 1
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["fontFamily"])
    }

    /// Karar 11: aileyi BOŞ string'e (bundle default'u) çekmek de yan etkidir.
    func testEmptyFontFamilyPropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        var old = AppConfig.defaults
        old.terminalFontFamily = "Menlo"

        emit(harness, from: old) { $0.terminalFontFamily = "" }

        await waitUntil("boş font ailesi atlandı") {
            harness.box.recorder.fontFamilyCalls == 1
        }
    }

    // MARK: - 5. terminalCursorStyle / terminalCursorBlink (tek callback)

    func testCursorStyleChangeFiresCursorCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.terminalCursorStyle = TerminalCursorShape.bar.rawValue }

        await waitUntil("cursor callback'i çalışmadı") {
            harness.box.recorder.cursors.count == 1
        }
        XCTAssertEqual(harness.box.recorder.cursors.first?.shape, .bar)
        XCTAssertEqual(harness.box.recorder.cursors.first?.blink, AppConfig.defaults.terminalCursorBlink)
        XCTAssertEqual(harness.box.recorder.firedKinds, ["cursor"])
    }

    /// Blink kapatmak (true → false) da aynı callback'ten akar.
    func testCursorBlinkDisabledPropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.terminalCursorBlink = false }

        await waitUntil("blink değişimi atlandı") {
            harness.box.recorder.cursors.count == 1
        }
        XCTAssertEqual(harness.box.recorder.cursors.first?.blink, false)
        XCTAssertEqual(harness.box.recorder.cursors.first?.shape, .block)
    }

    /// Şekil + blink birlikte değişse bile TEK çağrı olur (ikisi bir CursorStyle).
    func testCursorStyleAndBlinkChangeTogetherFireOnce() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) {
            $0.terminalCursorStyle = TerminalCursorShape.underline.rawValue
            $0.terminalCursorBlink = false
        }

        await waitUntil("cursor callback'i çalışmadı") {
            harness.box.recorder.cursors.count == 1
        }
        XCTAssertEqual(harness.box.recorder.cursors.first?.shape, .underline)
        XCTAssertEqual(harness.box.recorder.cursors.first?.blink, false)
    }

    // MARK: - 6. autoMinimizeOnSend (karar 24)

    func testAutoMinimizeChangeFiresOnlyItsCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) { $0.autoMinimizeOnSend = true }

        await waitUntil("autoMinimize callback'i çalışmadı") {
            harness.box.recorder.autoMinimize == [true]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["autoMinimize"])
    }

    /// Karar 11: `false` da propagate edilir (kapatma sinyali kaybolmaz).
    func testAutoMinimizeDisabledPropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        var old = AppConfig.defaults
        old.autoMinimizeOnSend = true

        emit(harness, from: old) { $0.autoMinimizeOnSend = false }

        await waitUntil("false değeri atlandı") {
            harness.box.recorder.autoMinimize == [false]
        }
    }

    // MARK: - 7. sessionTrigger

    func testSessionTriggerChangeFiresOnlyItsCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        let trigger = SessionTrigger(enabled: true, hour: 7, minute: 30, prompt: "go")

        emit(harness) { $0.sessionTrigger = trigger }

        await waitUntil("sessionTrigger callback'i çalışmadı") {
            harness.box.recorder.sessionTriggers == [trigger]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["sessionTrigger"])
    }

    // MARK: - 8. usageAutoRefresh (karar 20)

    func testUsageAutoRefreshChangeFiresOnlyItsCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        let refresh = UsageAutoRefresh(enabled: true, intervalMinutes: 1)

        emit(harness) { $0.usageAutoRefresh = refresh }

        await waitUntil("usageAutoRefresh callback'i çalışmadı") {
            harness.box.recorder.usageAutoRefresh == [refresh]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["usageAutoRefresh"])
    }

    // MARK: - 9. usageIndicators (karar 32)

    func testUsageIndicatorsChangeFiresOnlyItsCallback() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        let indicators = UsageIndicators(claude: false, codex: true)

        emit(harness) { $0.usageIndicators = indicators }

        await waitUntil("usageIndicators callback'i çalışmadı") {
            harness.box.recorder.usageIndicators == [indicators]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["usageIndicators"])
    }

    /// Karar 11: her göstergeyi KAPATMAK da yan etkidir (istekler durmalı).
    func testDisablingAllUsageIndicatorsPropagates() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        let off = UsageIndicators(claude: false, codex: false)

        emit(harness) { $0.usageIndicators = off }

        await waitUntil("kapatma sinyali atlandı") {
            harness.box.recorder.usageIndicators == [off]
        }
    }

    // MARK: - Değişmeyen alanlar hiçbir şeyi tetiklemez

    func testIdenticalConfigFiresNothing() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        harness.config.emitConfigChange(old: .defaults, new: .defaults)
        // Kanıtlayıcı ikinci event: bu işlendiyse ilki de işlenmiştir.
        emit(harness) { $0.terminalFontSize = 42 }

        await waitUntil("sentinel event işlenmedi") {
            harness.box.recorder.fontSizes == [42]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["fontSize"])
        XCTAssertTrue(harness.notifications.settingsUpdates.isEmpty)
        let calls = await harness.repo.setRootsCalls
        XCTAssertTrue(calls.isEmpty)
    }

    /// Diff kuralı olmayan alanlar (theme, aiProvider) hiçbir callback sürmez.
    func testUnwatchedFieldsFireNothing() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }

        emit(harness) {
            $0.theme = "light"
            $0.aiProvider = .codex
        }
        emit(harness) { $0.terminalFontSize = 42 } // sentinel

        await waitUntil("sentinel event işlenmedi") {
            harness.box.recorder.fontSizes == [42]
        }
        XCTAssertEqual(harness.box.recorder.firedKinds, ["fontSize"])
    }

    // MARK: - Yaşam döngüsü

    func testStopHaltsPropagation() async {
        let harness = await makeHarness()
        harness.coordinator.stop()

        emit(harness) { $0.terminalFontSize = 18 }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(harness.box.recorder.firedKinds, [], "stop sonrası event işlenmez")
    }

    func testStartIsIdempotent() async {
        let harness = await makeHarness()
        defer { harness.coordinator.stop() }
        harness.coordinator.start() // ikinci çağrı yeni tüketici kurmamalı

        emit(harness) { $0.terminalFontSize = 18 }

        await waitUntil("event işlenmedi") { !harness.box.recorder.fontSizes.isEmpty }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(harness.box.recorder.fontSizes, [18], "event iki kez işlenmemeli")
    }

    // MARK: - Yardımcı

    private func pollSetRoots(_ harness: Harness) async -> [FakeRepoService.RootsCall] {
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            let calls = await harness.repo.setRootsCalls
            if !calls.isEmpty { return calls }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("setRoots hiç çağrılmadı")
        return []
    }
}
