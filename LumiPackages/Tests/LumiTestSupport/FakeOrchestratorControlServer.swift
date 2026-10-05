import Foundation
import LumiKit

/// Test için sahte MCP sunucusu (karar 114 Faz 2): ağ açmaz, verilen
/// handler'ı saklar ki testler araçları doğrudan çağırabilsin.
public final class FakeOrchestratorControlServer: OrchestratorControlServing, @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (any OrchestratorToolHandling)?
    private var _startCount = 0
    private var _stopCount = 0
    private var startError: LumiError?

    public static let endpoint = OrchestratorControlEndpoint(port: 4242, token: "fake-token")

    public init() {}

    public var handler: (any OrchestratorToolHandling)? { lock.withLock { _handler } }
    public var startCount: Int { lock.withLock { _startCount } }
    public var stopCount: Int { lock.withLock { _stopCount } }

    public func stubStartError(_ error: LumiError?) { lock.withLock { startError = error } }

    public func start(handler: any OrchestratorToolHandling) async throws -> OrchestratorControlEndpoint {
        try lock.withLock {
            if let startError { throw startError }
            _handler = handler
            _startCount += 1
            return Self.endpoint
        }
    }

    public func stop() async {
        lock.withLock { _stopCount += 1 }
    }
}

/// Test için sahte transkript okuyucu: (sessionID, cwd) → mesajlar.
public final class FakeTerminalTranscripts: TerminalTranscriptReading, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String: [ChatMessage]] = [:]

    public init() {}

    public func stub(sessionID: String, cwd: String, messages: [ChatMessage]) {
        lock.withLock { self.messages["\(cwd)|\(sessionID)"] = messages }
    }

    public func recentClaudeMessages(sessionID: String, cwd: String) async -> [ChatMessage] {
        lock.withLock { messages["\(cwd)|\(sessionID)"] ?? [] }
    }
}
