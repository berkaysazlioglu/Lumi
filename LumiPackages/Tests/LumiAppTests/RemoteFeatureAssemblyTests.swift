import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiAppCore

/// Karar 143, Faz 5: remote araç sunucusu açılışta kalkar ve adresi + token'ı
/// Claude terminallerinin ortamına yazılır (`lumi-remote` modunun `.mcp.json`'ı açar).
@MainActor
final class RemoteFeatureAssemblyTests: XCTestCase {
    func testStartPublishesTheRemoteToolServerToClaudeTerminals() async throws {
        let registry = FakeServiceRegistry()
        defer { registry.removeTemporaryDirectories() }
        let shared = SharedStores.make(config: registry.config, terminal: registry.terminal, toastAutoDismissAfter: 60)
        let assembly = RemoteFeatureAssembly(usage: UsageFeatureAssembly())
        assembly.build(services: registry, shared: shared)
        await assembly.start()

        XCTAssertEqual(registry.fakeTerminal.launchEnvironments[.claude], FakeRemoteMCPServer.endpoint.environment)
        XCTAssertNil(registry.fakeTerminal.launchEnvironments[.codex], "yalnız Claude terminalleri")
        let server = try XCTUnwrap(registry.remoteMCP as? FakeRemoteMCPServer)
        XCTAssertTrue(server.handler is RemoteMCPToolbox)
        await assembly.shutdown()
        XCTAssertNil(server.handler)
    }
}
