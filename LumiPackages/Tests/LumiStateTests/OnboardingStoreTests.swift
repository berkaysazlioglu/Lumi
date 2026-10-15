import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Onboarding akışı (refactor 5.8): adım sırası, "fail bloklar / warn
/// bloklamaz" kuralı (design/03 §4 bağlayıcı), check yürütme ve tamamlama.
@MainActor
final class OnboardingStoreTests: XCTestCase {
    private struct Fixture {
        let store: OnboardingStore
        let system: FakeSystemService
        let settings: SettingsStore
        let config: FakeConfigService
        let toasts: ToastStore
        let completions: Box
    }

    /// Callback sayacı (struct içinden yazılabilsin diye referans kutu).
    private final class Box {
        var count = 0
    }

    private func makeFixture() -> Fixture {
        let system = FakeSystemService()
        let config = FakeConfigService()
        let toasts = ToastStore(autoDismissAfter: 60)
        let settings = SettingsStore(config: config, toasts: toasts)
        let box = Box()
        let store = OnboardingStore(
            system: system,
            settings: settings,
            toasts: toasts,
            onComplete: { box.count += 1 }
        )
        return Fixture(
            store: store,
            system: system,
            settings: settings,
            config: config,
            toasts: toasts,
            completions: box
        )
    }

    private func check(
        _ id: String,
        _ status: SystemCheckResult.Status,
        fixURL: URL? = nil
    ) -> SystemCheckResult {
        SystemCheckResult(
            id: id,
            label: id,
            status: status,
            message: "",
            isFixable: fixURL != nil,
            fixURL: fixURL
        )
    }

    // MARK: - Adım akışı

    func testStartsOnWelcomeStep() {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.store.step, .welcome)
        XCTAssertTrue(fixture.store.isFirstStep)
        XCTAssertFalse(fixture.store.isLastStep)
    }

    func testAdvanceWalksThroughEveryStepInOrder() async {
        let fixture = makeFixture()
        let store = fixture.store

        store.advance()
        XCTAssertEqual(store.step, .checks)

        await store.runChecks() // pass'lerle kapı açılır
        store.advance()
        XCTAssertEqual(store.step, .done, "karar 119: projeler kökü adımı yok")
        XCTAssertTrue(store.isLastStep)
    }

    func testAdvanceOnLastStepDoesNotOverflow() async {
        let fixture = makeFixture()
        let store = fixture.store
        await store.runChecks()

        for _ in 0..<10 { store.advance() }

        XCTAssertEqual(store.step, .done, "son adımın ötesine geçilmez")
    }

    func testBackWalksBackAndStopsAtFirstStep() {
        let fixture = makeFixture()
        let store = fixture.store
        store.advance()
        store.back()
        XCTAssertEqual(store.step, .welcome)
        store.back()
        XCTAssertEqual(store.step, .welcome, "ilk adımın gerisine gidilmez")
    }

    // MARK: - fail bloklar, warn bloklamaz (design/03 §4)

    func testFailingCheckBlocksAdvance() async {
        let fixture = makeFixture()
        fixture.system.setCheckResults([check("git", .pass), check("claude", .fail)])
        fixture.store.advance()

        await fixture.store.runChecks()

        XCTAssertFalse(fixture.store.canAdvance)
    }

    func testWarningCheckDoesNotBlockAdvance() async {
        let fixture = makeFixture()
        fixture.system.setCheckResults([check("git", .pass), check("codex", .warn)])
        fixture.store.advance()

        await fixture.store.runChecks()

        XCTAssertTrue(fixture.store.canAdvance)
    }

    func testChecksStepBlocksAdvanceWhileChecksAreRunning() async {
        let fixture = makeFixture()
        fixture.system.setRunChecksDelay(.milliseconds(120))
        fixture.system.setCheckResults([check("git", .pass)])
        fixture.store.advance()

        let running = Task { await fixture.store.runChecks() }
        await Task.yield()
        XCTAssertTrue(fixture.store.isRunningChecks)
        XCTAssertFalse(fixture.store.canAdvance, "kontroller koşarken ilerlenemez")

        await running.value
        XCTAssertFalse(fixture.store.isRunningChecks)
        XCTAssertTrue(fixture.store.canAdvance)
    }

    // MARK: - Check yürütme

    func testRunChecksIfNeededRunsOnceAndReRunIsExplicit() async {
        let fixture = makeFixture()
        fixture.system.setCheckResults([check("git", .pass)])

        await fixture.store.runChecksIfNeeded()
        await fixture.store.runChecksIfNeeded()
        XCTAssertEqual(fixture.system.runChecksCalls.count, 1, "ikinci giriş yeniden koşmaz")

        await fixture.store.runChecks()
        XCTAssertEqual(fixture.system.runChecksCalls.count, 2)
        XCTAssertEqual(fixture.store.checks.map(\.id), ["git"])
    }

    /// Kontroller welcome adımında SEÇİLEN sağlayıcıya göre koşar
    /// (claude/codex CLI kontrolünün fail/warn ayrımı buna bağlı).
    func testRunChecksUsesSelectedProvider() async {
        let fixture = makeFixture()
        fixture.store.provider = .codex

        await fixture.store.runChecks()

        XCTAssertEqual(fixture.system.runChecksCalls, [.codex])
    }

    func testFixOpensCheckFixURL() {
        let fixture = makeFixture()
        let url = URL(string: "https://example.com/install")!

        fixture.store.fix(check("claude", .fail, fixURL: url))

        XCTAssertEqual(fixture.system.openedExternalURLs, [url])
    }

    func testFixWithoutURLDoesNothing() {
        let fixture = makeFixture()
        fixture.store.fix(check("claude", .fail))
        XCTAssertTrue(fixture.system.openedExternalURLs.isEmpty)
    }

    /// Karar 5: engellenen URL sessizce yutulmaz.
    func testFixReportsBlockedURLAsToast() {
        let fixture = makeFixture()
        let url = URL(string: "https://example.com/install")!
        fixture.system.setOpenExternalError(.externalURLBlocked(url))

        fixture.store.fix(check("claude", .fail, fixURL: url))

        XCTAssertEqual(fixture.toasts.toasts.count, 1)
        XCTAssertEqual(fixture.toasts.toasts.first?.kind, .error)
    }

    // MARK: - Tamamlama

    func testCompleteWritesProviderAndOnboardingFlagThenFiresCallback() async {
        let fixture = makeFixture()
        fixture.store.provider = .codex

        fixture.store.complete()

        XCTAssertEqual(fixture.settings.current.aiProvider, .codex)
        XCTAssertTrue(fixture.settings.current.onboardingCompleted)
        XCTAssertEqual(fixture.settings.current.projectsRoot, "", "karar 119: kök sorulmaz")
        XCTAssertEqual(fixture.completions.count, 1)
    }
}
