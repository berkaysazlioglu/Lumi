import Foundation
import LumiKit

/// `AgentHookServing` sahtesi (karar 45): sabit uç nokta döndürür, test
/// `emit(_:)` ile hook olayı sürer.
public final class FakeAgentHookServer: AgentHookServing, @unchecked Sendable {
    public let endpoint: AgentHookEndpoint
    private let broadcaster = EventBroadcaster<AgentHookEvent>()
    private let lock = NSLock()
    private var _startCount = 0
    private var _stopCount = 0
    /// Açıkken `start()` fırlatır (port alınamadı senaryosu).
    public var startError: LumiError?

    public init(endpoint: AgentHookEndpoint = AgentHookEndpoint(port: 43210, token: "fake-token")) {
        self.endpoint = endpoint
    }

    public var startCount: Int { lock.withLock { _startCount } }
    public var stopCount: Int { lock.withLock { _stopCount } }

    public func start() async throws -> AgentHookEndpoint {
        lock.withLock { _startCount += 1 }
        if let startError { throw startError }
        return endpoint
    }

    public func stop() async {
        lock.withLock { _stopCount += 1 }
    }

    public func events() -> AsyncStream<AgentHookEvent> {
        broadcaster.stream()
    }

    public func emit(_ event: AgentHookEvent) {
        broadcaster.send(event)
    }
}

/// `AgentHookInstalling` sahtesi: çağrı sayar, verilen sonucu döndürür.
public actor FakeAgentHookInstaller: AgentHookInstalling {
    public private(set) var installCount = 0
    public private(set) var uninstallCount = 0
    public var results: [AgentHookInstallResult] = AgentProvider.allCases.map {
        AgentHookInstallResult(provider: $0, outcome: .installed)
    }

    public init() {}

    public func setResults(_ results: [AgentHookInstallResult]) {
        self.results = results
    }

    public func install() async -> [AgentHookInstallResult] {
        installCount += 1
        return results
    }

    public func uninstall() async -> [AgentHookInstallResult] {
        uninstallCount += 1
        return results.map { AgentHookInstallResult(provider: $0.provider, outcome: .removed) }
    }
}
