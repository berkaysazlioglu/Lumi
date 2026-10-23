import Foundation
import LumiKit

/// `OrchestratorLaunching` sahtesi (karar 123): istekleri ve kuyruklanan
/// mesajları kaydeder; `codex` yokluğu ve kuyruk hatası programlanabilir.
public final class FakeOrchestratorLauncher: OrchestratorLaunching, @unchecked Sendable {
    public struct Queued: Equatable, Sendable {
        public let message: String
        public let thread: String
        public let codexHome: String?
    }

    private let lock = NSLock()
    private var _requests: [OrchestratorLaunchRequest] = []
    private var _queued: [Queued] = []
    private var _isCodexMissing = false
    private var _queueError: LumiError?

    public init() {}

    public var requests: [OrchestratorLaunchRequest] { lock.withLock { _requests } }
    public var queued: [Queued] { lock.withLock { _queued } }

    public func setCodexMissing(_ missing: Bool) { lock.withLock { _isCodexMissing = missing } }
    public func failQueue(with error: LumiError?) { lock.withLock { _queueError = error } }

    /// Planın komutu: hangi açılış olduğu testte okunabilsin.
    public static func command(for request: OrchestratorLaunchRequest) -> String {
        "codex " + (request.resumeThreadID.map { "resume \($0)" } ?? "new")
    }

    public func prepare(_ request: OrchestratorLaunchRequest) async throws -> OrchestratorLaunchPlan {
        try lock.withLock {
            if _isCodexMissing { throw LumiError.cliNotFound(binary: "codex") }
            _requests.append(request)
        }
        var environment: [String: String] = [:]
        if let home = request.codexHome { environment["CODEX_HOME"] = home }
        if let control = request.control { environment["LUMI_MCP_TOKEN"] = control.token }
        return OrchestratorLaunchPlan(command: Self.command(for: request), environment: environment)
    }

    public func queue(_ message: String, thread: String, codexHome: String?) async throws {
        try lock.withLock {
            if let _queueError { throw _queueError }
            _queued.append(Queued(message: message, thread: thread, codexHome: codexHome))
        }
    }
}
