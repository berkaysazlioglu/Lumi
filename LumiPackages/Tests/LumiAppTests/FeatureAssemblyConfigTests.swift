import Foundation
import XCTest
import LumiKit
import LumiState
import LumiTestSupport
@testable import LumiAppCore

/// Config yan etki diff kurallarının YENİ evi (refactor 3.3).
///
/// Eskiden `ConfigSideEffectCoordinator`'ın 8 `if` bloğunda toplanan 9 kural
/// artık ilgili feature assembly'sinin `configDidChange(old:new:)` gövdesinde.
/// Karakterizasyon kalkanı aynı: her kural için (a) YALNIZ ilgili yan etki
/// oluşur, (b) "falsy" değerler (0, "", false, boş dizi) de propagate edilir —
/// Electron'un truthiness bug'ı (karar 11) geri gelemez.
@MainActor
final class FeatureAssemblyConfigTests: XCTestCase {
    private var registry: FakeServiceRegistry!
    private var shared: SharedStores!

    override func setUp() async throws {
        registry = FakeServiceRegistry()
        shared = SharedStores.make(
            config: registry.config,
            terminal: registry.terminal,
            toastAutoDismissAfter: 60
        )
    }

    override func tearDown() async throws {
        registry.removeTemporaryDirectories()
        registry = nil
        shared = nil
    }

    private func build<T: FeatureAssembly>(_ assembly: T) -> T {
        assembly.build(services: registry, shared: shared)
        return assembly
    }

    /// `old` her testte aynı taban; `new` yalnız test edilen alanda farklıdır.
    private func changed(from old: AppConfig = .defaults, _ mutate: (inout AppConfig) -> Void)
        -> (old: AppConfig, new: AppConfig) {
        var new = old
        mutate(&new)
        return (old, new)
    }

    // MARK: - 1. projectsRoot / additionalPaths → RepoFeatureAssembly

    func testProjectsRootChangePropagatesRootsToRepoService() async {
        let assembly = build(RepoFeatureAssembly())
        let change = changed { $0.projectsRoot = "/tmp/projects" }

        assembly.configDidChange(old: change.old, new: change.new)

        let calls = await pollSetRoots()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.projectsRoot, "/tmp/projects")
    }

    /// Karar 11: projectsRoot BOŞ STRING'e düşse de yan etki atlanmaz.
    func testEmptyProjectsRootStillPropagates() async {
        let assembly = build(RepoFeatureAssembly())
        var old = AppConfig.defaults
        old.projectsRoot = "/tmp/projects"
        let change = changed(from: old) { $0.projectsRoot = "" }

        assembly.configDidChange(old: change.old, new: change.new)

        let calls = await pollSetRoots()
        XCTAssertEqual(calls.first?.projectsRoot, "", "boş string de propagate edilir")
    }

    func testAdditionalPathsChangeUpdatesRepoStore() async {
        let assembly = build(RepoFeatureAssembly())
        let path = AdditionalPath(id: "a", path: "/tmp/extra", type: .root, label: "Extra")
        let change = changed { $0.additionalPaths = [path] }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(assembly.repoStore.additionalPaths, [path], "store senkron güncellenir")
        let calls = await pollSetRoots()
        XCTAssertEqual(calls.first?.additionalPaths, [path])
    }

    /// Karar 11: dolu listeden BOŞ listeye geçiş de bir değişimdir.
    func testEmptyingAdditionalPathsStillPropagates() async {
        let assembly = build(RepoFeatureAssembly())
        var old = AppConfig.defaults
        old.additionalPaths = [AdditionalPath(id: "a", path: "/tmp/extra", type: .root)]
        let change = changed(from: old) { $0.additionalPaths = [] }

        assembly.configDidChange(old: change.old, new: change.new)

        let calls = await pollSetRoots()
        XCTAssertEqual(calls.first?.additionalPaths, [])
        XCTAssertEqual(assembly.repoStore.additionalPaths, [])
    }

    func testUnrelatedFieldDoesNotTouchRepoService() async {
        let assembly = build(RepoFeatureAssembly())
        let change = changed { $0.terminalFontSize = 18 }

        assembly.configDidChange(old: change.old, new: change.new)
        try? await Task.sleep(for: .milliseconds(30))

        let calls = await registry.fakeRepo.setRootsCalls
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - 2. notifications → NotificationAssembly

    func testNotificationSettingsChangePropagates() {
        let assembly = build(NotificationAssembly())
        var settings = NotificationSettings.defaults
        settings.unseenEnabled.toggle()
        let change = changed { $0.notifications = settings }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeNotifications.settingsUpdates, [settings])
    }

    func testUnchangedNotificationSettingsFireNothing() {
        let assembly = build(NotificationAssembly())
        let change = changed { $0.theme = "light" }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertTrue(registry.fakeNotifications.settingsUpdates.isEmpty)
    }

    // MARK: - 3/4. terminalFontSize + terminalFontFamily → TerminalFeatureAssembly

    func testFontSizeChangeAppliesFont() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed { $0.terminalFontSize = 18 }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedFonts.count, 1)
        XCTAssertEqual(registry.fakeTerminal.appliedFonts.first?.pointSize, 18)
        XCTAssertTrue(registry.fakeTerminal.appliedCursors.isEmpty, "cursor'a dokunulmaz")
    }

    /// Karar 11: 0 "falsy"dir ama yine de bir değişimdir.
    func testZeroFontSizePropagates() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed { $0.terminalFontSize = 0 }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedFonts.count, 1)
    }

    func testFontFamilyChangeAppliesFont() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed { $0.terminalFontFamily = "Menlo" }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedFonts.count, 1)
    }

    /// Karar 11: aileyi BOŞ string'e (bundle default'u) çekmek de yan etkidir.
    func testEmptyFontFamilyPropagates() {
        let assembly = build(TerminalFeatureAssembly())
        var old = AppConfig.defaults
        old.terminalFontFamily = "Menlo"
        let change = changed(from: old) { $0.terminalFontFamily = "" }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedFonts.count, 1)
    }

    /// Aile + boyut birlikte değişse bile TEK NSFont kurulur.
    func testFamilyAndSizeChangeTogetherApplyFontOnce() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed {
            $0.terminalFontFamily = "Menlo"
            $0.terminalFontSize = 15
        }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedFonts.count, 1)
        XCTAssertEqual(registry.fakeTerminal.appliedFonts.first?.pointSize, 15)
    }

    // MARK: - 5. cursor style / blink (tek yan etki)

    func testCursorStyleChangeAppliesCursor() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed { $0.terminalCursorStyle = TerminalCursorShape.bar.rawValue }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedCursors.count, 1)
        XCTAssertEqual(registry.fakeTerminal.appliedCursors.first?.shape, .bar)
        XCTAssertEqual(
            registry.fakeTerminal.appliedCursors.first?.blink,
            AppConfig.defaults.terminalCursorBlink
        )
        XCTAssertTrue(registry.fakeTerminal.appliedFonts.isEmpty, "font'a dokunulmaz")
    }

    func testCursorBlinkDisabledPropagates() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed { $0.terminalCursorBlink = false }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedCursors.first?.blink, false)
        XCTAssertEqual(registry.fakeTerminal.appliedCursors.first?.shape, .block)
    }

    /// Şekil + blink birlikte değişse bile TEK çağrı (ikisi bir CursorStyle).
    func testCursorStyleAndBlinkChangeTogetherFireOnce() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed {
            $0.terminalCursorStyle = TerminalCursorShape.underline.rawValue
            $0.terminalCursorBlink = false
        }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(registry.fakeTerminal.appliedCursors.count, 1)
        XCTAssertEqual(registry.fakeTerminal.appliedCursors.first?.shape, .underline)
        XCTAssertEqual(registry.fakeTerminal.appliedCursors.first?.blink, false)
    }

    // MARK: - 6. autoMinimizeOnSend (karar 24)

    func testAutoMinimizeChangeMirrorsIntoTerminalStore() {
        let assembly = build(TerminalFeatureAssembly())
        let change = changed { $0.autoMinimizeOnSend = true }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertTrue(shared.terminals.autoMinimizeOnSend)
    }

    /// Karar 11: `false` da propagate edilir (kapatma sinyali kaybolmaz).
    func testAutoMinimizeDisabledPropagates() {
        let assembly = build(TerminalFeatureAssembly())
        shared.terminals.autoMinimizeOnSend = true
        var old = AppConfig.defaults
        old.autoMinimizeOnSend = true
        let change = changed(from: old) { $0.autoMinimizeOnSend = false }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertFalse(shared.terminals.autoMinimizeOnSend)
    }

    // MARK: - 7. sessionTrigger → SessionScheduleAssembly

    func testSessionTriggerChangeReschedules() {
        let assembly = build(SessionScheduleAssembly())
        let trigger = SessionTrigger(enabled: true, hour: 7, minute: 30, prompt: "go")
        let change = changed { $0.sessionTrigger = trigger }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertNotNil(assembly.sessionSchedule.nextFireDate, "tetikleyici kuruldu")
        assembly.sessionSchedule.stop()
    }

    func testUnchangedSessionTriggerDoesNotSchedule() {
        let assembly = build(SessionScheduleAssembly())
        let change = changed { $0.theme = "light" }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertNil(assembly.sessionSchedule.nextFireDate)
    }

    // MARK: - 8. usageAutoRefresh (karar 20)

    func testUsageAutoRefreshChangeRestartsLoop() {
        let assembly = build(UsageFeatureAssembly())
        let refresh = UsageAutoRefresh(enabled: true, intervalMinutes: 1)
        let change = changed { $0.usageAutoRefresh = refresh }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertTrue(assembly.usageAutoRefresh.isRunning)
        assembly.usageAutoRefresh.stop()
    }

    /// Karar 11: kapatma (`enabled: false`) da propagate edilir.
    func testDisablingUsageAutoRefreshStopsLoop() {
        let assembly = build(UsageFeatureAssembly())
        var old = AppConfig.defaults
        old.usageAutoRefresh = UsageAutoRefresh(enabled: true, intervalMinutes: 1)
        assembly.usageAutoRefresh.update(old.usageAutoRefresh)
        XCTAssertTrue(assembly.usageAutoRefresh.isRunning)
        let change = changed(from: old) {
            $0.usageAutoRefresh = UsageAutoRefresh(enabled: false, intervalMinutes: 1)
        }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertFalse(assembly.usageAutoRefresh.isRunning)
    }

    // MARK: - 9. usageIndicators (karar 32)

    func testUsageIndicatorsChangeFlipsStoreGates() {
        let assembly = build(UsageFeatureAssembly())
        let change = changed { $0.usageIndicators = UsageIndicators(claude: false, codex: true) }

        assembly.configDidChange(old: change.old, new: change.new)

        XCTAssertEqual(assembly.usageStores[.claude]?.isEnabled, false)
        XCTAssertEqual(assembly.usageStores[.codex]?.isEnabled, true)
    }

    /// Karar 11: her göstergeyi KAPATMAK da yan etkidir (istekler durmalı).
    func testDisablingAllUsageIndicatorsPropagates() {
        let assembly = build(UsageFeatureAssembly())
        let change = changed { $0.usageIndicators = UsageIndicators(claude: false, codex: false) }

        assembly.configDidChange(old: change.old, new: change.new)

        for provider in AgentProvider.allCases {
            XCTAssertEqual(assembly.usageStores[provider]?.isEnabled, false)
        }
    }

    // MARK: - Değişmeyen config hiçbir şeyi tetiklemez

    func testIdenticalConfigFiresNothingAnywhere() async {
        let terminal = build(TerminalFeatureAssembly())
        let notifications = build(NotificationAssembly())
        let repo = build(RepoFeatureAssembly())
        let usage = build(UsageFeatureAssembly())
        let schedule = build(SessionScheduleAssembly())

        for assembly in [terminal, notifications, repo, usage, schedule] as [any FeatureAssembly] {
            assembly.configDidChange(old: .defaults, new: .defaults)
        }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(registry.fakeTerminal.appliedFonts.isEmpty)
        XCTAssertTrue(registry.fakeTerminal.appliedCursors.isEmpty)
        XCTAssertTrue(registry.fakeNotifications.settingsUpdates.isEmpty)
        let calls = await registry.fakeRepo.setRootsCalls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(schedule.sessionSchedule.nextFireDate)
        XCTAssertFalse(usage.usageAutoRefresh.isRunning)
    }

    // MARK: - Yardımcı

    private func pollSetRoots() async -> [FakeRepoService.RootsCall] {
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            let calls = await registry.fakeRepo.setRootsCalls
            if !calls.isEmpty { return calls }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("setRoots hiç çağrılmadı")
        return []
    }
}
