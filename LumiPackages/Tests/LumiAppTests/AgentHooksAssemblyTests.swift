import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiAppCore

/// Karar 45: hook assembly'si — sunucu → uç nokta → terminal servisi, olay
/// akışı, kurulum ve ayar anahtarıyla aç/kapa.
@MainActor
final class AgentHooksAssemblyTests: XCTestCase {
    private var registry: FakeServiceRegistry!
    private var shared: SharedStores!
    private var assembly: AgentHooksAssembly!

    override func setUp() async throws {
        registry = FakeServiceRegistry()
        shared = SharedStores.make(config: registry.config, terminal: registry.terminal, toastAutoDismissAfter: 60)
        assembly = AgentHooksAssembly()
        assembly.build(services: registry, shared: shared)
    }

    override func tearDown() async throws {
        await assembly.shutdown()
        registry.removeTemporaryDirectories()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Kurulum ayrı bir Task'ta koşar; actor sayaçları beklenen değere gelene
    /// dek (en fazla 2 sn) yoklanır, sonra son hâl döner.
    private func installCounts(
        expecting expected: (install: Int, uninstall: Int)
    ) async -> (install: Int, uninstall: Int) {
        let deadline = ContinuousClock.now + .seconds(2)
        var current = (install: 0, uninstall: 0)
        while ContinuousClock.now < deadline {
            current.install = await registry.fakeAgentHookInstaller.installCount
            current.uninstall = await registry.fakeAgentHookInstaller.uninstallCount
            if current == expected { return current }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return current
    }

    func testStartPublishesEndpointInstallsHooksAndForwardsEvents() async {
        await assembly.start()

        XCTAssertEqual(registry.fakeAgentHooks.startCount, 1)
        XCTAssertEqual(registry.fakeTerminal.hookEndpoints, [registry.fakeAgentHooks.endpoint])
        let counts = await installCounts(expecting: (1, 0))
        XCTAssertEqual(counts.install, 1)
        XCTAssertEqual(counts.uninstall, 0)

        let event = AgentHookEvent(provider: .claude, terminalID: TerminalID(), kind: .stop)
        registry.fakeAgentHooks.emit(event)
        let forwarded = await waitUntil { self.registry.fakeTerminal.appliedHookEvents == [event] }
        XCTAssertTrue(forwarded, "olay terminal servisine iletilmedi")
    }

    func testDisabledConfigStartsNothing() async {
        var config = AppConfig.defaults
        config.agentHooksEnabled = false
        await registry.fakeConfig.seed(config)

        await assembly.start()

        XCTAssertEqual(registry.fakeAgentHooks.startCount, 0)
        XCTAssertTrue(registry.fakeTerminal.hookEndpoints.isEmpty)
        let installCount = await registry.fakeAgentHookInstaller.installCount
        XCTAssertEqual(installCount, 0)
    }

    func testServerFailureShowsToastAndLeavesTerminalWithoutEndpoint() async {
        registry.fakeAgentHooks.startError = .underlying(domain: "test", message: "port busy")

        await assembly.start()

        XCTAssertTrue(registry.fakeTerminal.hookEndpoints.isEmpty)
        XCTAssertEqual(shared.toasts.toasts.count, 1)
        XCTAssertFalse(assembly.isEnabled)
    }

    func testTogglingOffStopsServerClearsEndpointAndUninstalls() async {
        await assembly.start()
        var disabled = AppConfig.defaults
        disabled.agentHooksEnabled = false

        assembly.configDidChange(old: .defaults, new: disabled)

        let stopped = await waitUntil { self.registry.fakeAgentHooks.stopCount == 1 }
        XCTAssertTrue(stopped)
        XCTAssertEqual(registry.fakeTerminal.hookEndpoints.last, .some(nil))
        let counts = await installCounts(expecting: (1, 1))
        XCTAssertEqual(counts.uninstall, 1, "kapatma yönetilen girdileri kaldırmalı")
    }

    func testTogglingOnStartsServerAgain() async {
        var disabled = AppConfig.defaults
        disabled.agentHooksEnabled = false
        await registry.fakeConfig.seed(disabled)
        await assembly.start()

        assembly.configDidChange(old: disabled, new: .defaults)

        let started = await waitUntil { self.registry.fakeAgentHooks.startCount == 1 }
        XCTAssertTrue(started)
        XCTAssertEqual(registry.fakeTerminal.hookEndpoints, [registry.fakeAgentHooks.endpoint])
    }

    func testShutdownStopsServerButKeepsHooksInstalled() async {
        await assembly.start()

        await assembly.shutdown()

        XCTAssertEqual(registry.fakeAgentHooks.stopCount, 1)
        let uninstallCount = await registry.fakeAgentHookInstaller.uninstallCount
        XCTAssertEqual(uninstallCount, 0)
    }
}
