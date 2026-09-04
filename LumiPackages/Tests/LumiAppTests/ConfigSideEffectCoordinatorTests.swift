import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiAppCore

/// `ConfigSideEffectCoordinator`'ın YENİ sözleşmesi (refactor 3.3): alan başına
/// callback yok — koordinatör `(old, new)` çiftini kayıtlı gözlemcilere dağıtan
/// ince bir köprüdür. Alan bazlı diff kuralları (karar 11 kalkanı dahil) artık
/// assembly testlerinde: `FeatureAssemblyConfigTests`.
@MainActor
final class ConfigSideEffectCoordinatorTests: XCTestCase {
    /// Dağıtımı kaydeden minimal gözlemci.
    private final class RecordingObserver: ConfigChangeObserving {
        private(set) var changes: [(old: AppConfig, new: AppConfig)] = []
        func configDidChange(old: AppConfig, new: AppConfig) {
            changes.append((old, new))
        }
    }

    private func makeCoordinator() -> (ConfigSideEffectCoordinator, FakeConfigService) {
        let config = FakeConfigService()
        return (ConfigSideEffectCoordinator(config: config), config)
    }

    /// Plan 5.6: `events()` nonisolated olduğundan abonelik `start()` DÖNMEDEN
    /// kuruludur — boot penceresinde event kaybolmaz. Eski kod stream'i Task
    /// içinde `await` ile alıyordu ve bu testi geçemezdi.
    func testSubscriptionIsEstablishedSynchronouslyByStart() async {
        let (coordinator, config) = makeCoordinator()
        defer { coordinator.stop() }
        let observer = RecordingObserver()
        coordinator.register(observer)

        coordinator.start()
        XCTAssertEqual(config.subscriberCount, 1, "abonelik start() dönmeden kurulmalı")

        var new = AppConfig.defaults
        new.terminalFontSize = 18
        config.emitConfigChange(old: .defaults, new: new)

        await waitUntil("event dağıtılmadı") { observer.changes.count == 1 }
        XCTAssertEqual(observer.changes.first?.new.terminalFontSize, 18)
    }

    func testDispatchesToEveryObserverInRegistrationOrder() {
        let (coordinator, _) = makeCoordinator()
        let first = RecordingObserver()
        let second = RecordingObserver()
        coordinator.register(first)
        coordinator.register(second)

        var new = AppConfig.defaults
        new.theme = "light"
        coordinator.dispatch(old: .defaults, new: new)

        XCTAssertEqual(first.changes.count, 1)
        XCTAssertEqual(second.changes.count, 1)
        XCTAssertEqual(second.changes.first?.new.theme, "light")
    }

    /// Koordinatör diff YAPMAZ: eşit config bile gözlemcilere iletilir, "değişti mi"
    /// kararı gözlemcinindir (karar 11 eşitlik-tabanlı diff her assembly'de).
    func testIdenticalConfigIsStillForwardedToObservers() {
        let (coordinator, _) = makeCoordinator()
        let observer = RecordingObserver()
        coordinator.register(observer)

        coordinator.dispatch(old: .defaults, new: .defaults)

        XCTAssertEqual(observer.changes.count, 1)
    }

    func testStopHaltsPropagation() async {
        let (coordinator, config) = makeCoordinator()
        let observer = RecordingObserver()
        coordinator.register(observer)
        coordinator.start()

        coordinator.stop()
        var new = AppConfig.defaults
        new.terminalFontSize = 18
        config.emitConfigChange(old: .defaults, new: new)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(observer.changes.isEmpty, "stop sonrası event dağıtılmaz")
    }

    func testStartIsIdempotent() async {
        let (coordinator, config) = makeCoordinator()
        defer { coordinator.stop() }
        let observer = RecordingObserver()
        coordinator.register(observer)

        coordinator.start()
        coordinator.start() // ikinci çağrı yeni tüketici kurmamalı
        XCTAssertEqual(config.subscriberCount, 1)

        var new = AppConfig.defaults
        new.terminalFontSize = 18
        config.emitConfigChange(old: .defaults, new: new)

        await waitUntil("event dağıtılmadı") { !observer.changes.isEmpty }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(observer.changes.count, 1, "event iki kez dağıtılmamalı")
    }

    /// Yalnız `.configChanged` dağıtılır; hata event'leri gözlemciye gitmez.
    func testNonConfigChangeEventsAreIgnored() async {
        let (coordinator, config) = makeCoordinator()
        defer { coordinator.stop() }
        let observer = RecordingObserver()
        coordinator.register(observer)
        coordinator.start()

        config.emit(.loadFailed(file: "config.json", detail: "bozuk"))
        config.emit(.writeFailed(file: "ui-state.json", detail: "disk"))
        var new = AppConfig.defaults
        new.terminalFontSize = 42 // sentinel
        config.emitConfigChange(old: .defaults, new: new)

        await waitUntil("sentinel işlenmedi") { observer.changes.count == 1 }
        XCTAssertEqual(observer.changes.first?.new.terminalFontSize, 42)
    }
}
