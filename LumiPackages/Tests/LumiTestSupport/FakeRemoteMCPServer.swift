import Foundation
import LumiKit

/// Soketsiz `RemoteMCPServing` (karar 143, Faz 5): yürütücüyü saklar, sabit uç döner.
public final class FakeRemoteMCPServer: RemoteMCPServing, @unchecked Sendable {
    public static let endpoint = RemoteMCPEndpoint(port: 4343, token: "fake-remote-token")

    private let lock = NSLock()
    private var _handler: (any OrchestratorToolHandling)?

    public init() {}

    public var handler: (any OrchestratorToolHandling)? { lock.withLock { _handler } }

    public func start(handler: any OrchestratorToolHandling) async throws -> RemoteMCPEndpoint {
        lock.withLock { _handler = handler }
        return Self.endpoint
    }

    public func stop() async {
        lock.withLock { _handler = nil }
    }
}
