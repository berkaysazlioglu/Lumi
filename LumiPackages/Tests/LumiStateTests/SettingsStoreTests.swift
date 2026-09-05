import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// Ayar yazımının bayat snapshot'a değil TAZE `current`'a uygulanması (1.2) ve
/// optimistik güncellemenin diskle uzlaşması (1.16).
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var toasts: ToastStore!
    private var store: SettingsStore!

    override func setUp() async throws {
        config = FakeConfigService()
        toasts = ToastStore(autoDismissAfter: 60)
        store = SettingsStore(config: config, toasts: toasts)
    }

    /// Yazımlar fire-and-forget Task'ta; koşul sağlanana kadar yoklanır.
    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await !condition() {
            if Date() > deadline {
                return XCTFail("koşul sağlanmadı: \(description)")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 1.2 alan bazlı güncellemeler birbirini ezmez

    func testUpdateNotificationsKeepsPreviouslyChangedFields() async throws {
        store.updateNotifications { $0.unseenEnabled = false }
        store.updateNotifications { $0.seenIntervalMinutes = 30 }

        XCTAssertFalse(store.current.notifications.unseenEnabled)
        XCTAssertEqual(store.current.notifications.seenIntervalMinutes, 30)

        try await waitUntil("iki alan da diske indi") {
            let persisted = await self.config.config().notifications
            return persisted.unseenEnabled == false && persisted.seenIntervalMinutes == 30
        }
    }

    func testUpdateSessionTriggerKeepsPreviouslyChangedFields() async throws {
        store.updateSessionTrigger { $0.enabled = true }
        store.updateSessionTrigger { $0.prompt = "start" }

        XCTAssertTrue(store.current.sessionTrigger.enabled)
        XCTAssertEqual(store.current.sessionTrigger.prompt, "start")

        try await waitUntil("iki alan da diske indi") {
            let persisted = await self.config.config().sessionTrigger
            return persisted.enabled && persisted.prompt == "start"
        }
    }

    func testUpdateUsageAutoRefreshKeepsPreviouslyChangedFields() async throws {
        store.updateUsageAutoRefresh { $0.enabled = true }
        store.updateUsageAutoRefresh { $0.intervalMinutes = 1 }

        XCTAssertTrue(store.current.usageAutoRefresh.enabled)
        XCTAssertEqual(store.current.usageAutoRefresh.intervalMinutes, 1)

        try await waitUntil("iki alan da diske indi") {
            let persisted = await self.config.config().usageAutoRefresh
            return persisted.enabled && persisted.intervalMinutes == 1
        }
    }

    // MARK: - 1.16 optimistik güncelleme diskle uzlaşır

    func testApplyReconcilesCurrentWithServiceValue() async throws {
        // Servis yazımı normalize eder (izinsiz aralık default'a düşer): optimistik
        // değer değil, diskteki değer geçerli olmalı.
        store.setUsageAutoRefresh(UsageAutoRefresh(enabled: true, intervalMinutes: 5))
        try await waitUntil("uzlaşma tamamlandı") {
            await self.config.configUpdateCount == 1
                && self.store.current.usageAutoRefresh.intervalMinutes == 5
        }
    }

    func testApplyRevertsOptimisticValueWhenWriteFails() async throws {
        await config.setUpdateConfigError(.configIOFailed(file: "config.json", detail: "disk"))

        store.setProjectsRoot("/tmp/new-root")
        XCTAssertEqual(store.current.projectsRoot, "/tmp/new-root", "optimistik değer anında görünür")

        try await waitUntil("diskteki değere dönüldü") {
            self.store.current.projectsRoot == AppConfig.defaults.projectsRoot
        }
        XCTAssertEqual(toasts.toasts.count, 1, "karar 5: yazım hatası görünür")
    }

    // MARK: - refresh() (modal her açılışta taze config)

    func testRefreshPullsValueWrittenOutsideTheStore() async {
        var external = AppConfig.defaults
        external.projectsRoot = "/tmp/from-disk"
        await config.seed(external)

        XCTAssertEqual(store.current.projectsRoot, AppConfig.defaults.projectsRoot, "mount'ta bayat")
        await store.refresh()
        XCTAssertEqual(store.current.projectsRoot, "/tmp/from-disk")
    }

    func testRefreshIsIdempotent() async {
        await store.refresh()
        let first = store.current
        await store.refresh()
        XCTAssertEqual(store.current, first)
    }

    // MARK: - start() event tüketimi

    func testStartSeedsCurrentAndConsumesConfigChangedEvents() async throws {
        var seeded = AppConfig.defaults
        seeded.theme = "light"
        await config.seed(seeded)

        store.start()
        try await waitUntil("ilk okuma") { self.store.current.theme == "light" }

        var updated = seeded
        updated.terminalFontSize = 19
        config.emitConfigChange(old: seeded, new: updated)
        try await waitUntil("event uygulandı") { self.store.current.terminalFontSize == 19 }
    }

    func testStartIgnoresNonConfigChangedEvents() async throws {
        store.start()
        try await waitUntil("abonelik") { await self.config.subscriberCount >= 1 }
        let before = store.current

        config.emit(.writeFailed(file: "ui-state.json", detail: "disk full"))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.current, before, "yalnız configChanged uygulanır")
    }

    func testStartIsIdempotent() async throws {
        store.start()
        store.start()
        try await waitUntil("abonelik") { await self.config.subscriberCount >= 1 }
        try await Task.sleep(for: .milliseconds(50))
        let count = await config.subscriberCount
        XCTAssertEqual(count, 1, "ikinci start yeni tüketici açmamalı")
    }

    func testEventAfterStopDoesNotChangeState() async throws {
        store.start()
        try await waitUntil("abonelik") { await self.config.subscriberCount >= 1 }
        let before = store.current

        store.stop()
        var updated = before
        updated.theme = "solarized"
        config.emitConfigChange(old: before, new: updated)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.current, before, "stop sonrası event state'i değiştirmez")
    }

    // MARK: - Font boyutu clamp'i (10…24)

    func testFontSizeClampsToLowerBound() async throws {
        store.setTerminalFontSize(4)
        XCTAssertEqual(store.current.terminalFontSize, 10)
        try await waitUntil("clamp'lenmiş değer diske indi") {
            await self.config.config().terminalFontSize == 10
        }
    }

    func testFontSizeClampsToUpperBound() async throws {
        store.setTerminalFontSize(99)
        XCTAssertEqual(store.current.terminalFontSize, 24)
        try await waitUntil("clamp'lenmiş değer diske indi") {
            await self.config.config().terminalFontSize == 24
        }
    }

    /// Sınırların TEK tanımı modelde (refactor 5.7): store literal taşımaz.
    func testFontSizeBoundsComeFromTheModel() {
        XCTAssertEqual(AppConfig.terminalFontSizeRange, 10 ... 24)
        store.setTerminalFontSize(AppConfig.terminalFontSizeRange.upperBound + 1)
        XCTAssertEqual(
            store.current.terminalFontSize,
            AppConfig.terminalFontSizeRange.upperBound
        )
        store.setTerminalFontSize(AppConfig.terminalFontSizeRange.lowerBound - 1)
        XCTAssertEqual(
            store.current.terminalFontSize,
            AppConfig.terminalFontSizeRange.lowerBound
        )
    }

    func testFontSizeBoundsAreInclusive() {
        store.setTerminalFontSize(10)
        XCTAssertEqual(store.current.terminalFontSize, 10)
        store.setTerminalFontSize(24)
        XCTAssertEqual(store.current.terminalFontSize, 24)
        store.setTerminalFontSize(13)
        XCTAssertEqual(store.current.terminalFontSize, 13)
    }

    func testNegativeFontSizeIsClampedNotRejected() {
        store.setTerminalFontSize(-5)
        XCTAssertEqual(store.current.terminalFontSize, 10)
    }

    // MARK: - additionalPaths intent'leri

    func testAddAndRemoveAdditionalPath() async throws {
        store.addAdditionalPath("/tmp/extra", type: .root)
        XCTAssertEqual(store.current.additionalPaths.count, 1)
        let id = try XCTUnwrap(store.current.additionalPaths.first?.id)
        XCTAssertEqual(store.current.additionalPaths.first?.type, .root)

        try await waitUntil("ekleme diske indi") {
            await self.config.config().additionalPaths.count == 1
        }

        store.removeAdditionalPath(id: id)
        XCTAssertTrue(store.current.additionalPaths.isEmpty)
        try await waitUntil("silme diske indi") {
            await self.config.config().additionalPaths.isEmpty
        }
    }

    func testRemoveUnknownAdditionalPathIsNoop() {
        store.addAdditionalPath("/tmp/extra", type: .repo)
        store.removeAdditionalPath(id: "does-not-exist")
        XCTAssertEqual(store.current.additionalPaths.count, 1)
    }
}

// MARK: - 1.13 bozuk/yazılamayan config kullanıcıya görünür (karar 5)

extension SettingsStoreTests {
    func testLoadFailedEventShowsErrorToast() async throws {
        store.start()
        try await waitUntil("abonelik") { self.config.subscriberCount >= 1 }

        config.emit(.loadFailed(file: "config.json", detail: "unexpected token"))

        try await waitUntil("toast") { self.toasts.toasts.contains { $0.kind == .error } }
        XCTAssertTrue(toasts.toasts.contains { $0.title.contains("config.json") })
    }

    func testWriteFailedEventShowsErrorToast() async throws {
        store.start()
        try await waitUntil("abonelik") { self.config.subscriberCount >= 1 }

        config.emit(.writeFailed(file: "ui-state.json", detail: "EACCES"))

        try await waitUntil("toast") { self.toasts.toasts.contains { $0.kind == .error } }
        XCTAssertTrue(toasts.toasts.contains { $0.message.contains("EACCES") })
    }
}
