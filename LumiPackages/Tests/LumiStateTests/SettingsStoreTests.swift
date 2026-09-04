import Foundation
import XCTest
import LumiKit
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
}
