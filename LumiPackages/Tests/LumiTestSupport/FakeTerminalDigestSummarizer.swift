import Foundation
import LumiKit

/// Test için sahte özetleyici (karar 104 Faz 4): sabit özet ya da hata döner,
/// çağrıları kaydeder.
public final class FakeTerminalDigestSummarizer: TerminalDigestSummarizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private var _sessionRequests: [String] = []
    private var outcome: Result<TerminalDigest, LumiError> = .success(TerminalDigest(summary: "özet", needsUser: false))

    public init() {}

    /// `summarize` çağrılarının mesajları.
    public var requests: [String] { lock.withLock { _requests } }
    /// `summarizeSession` çağrılarının transkriptleri.
    public var sessionRequests: [String] { lock.withLock { _sessionRequests } }

    public func stub(_ outcome: Result<TerminalDigest, LumiError>) { lock.withLock { self.outcome = outcome } }

    public func summarize(agentMessage: String, terminalTitle: String) async throws -> TerminalDigest {
        let outcome = lock.withLock { () -> Result<TerminalDigest, LumiError> in
            _requests.append(agentMessage)
            return self.outcome
        }
        return try outcome.get()
    }

    public func summarizeSession(transcript: String, terminalTitle: String) async throws -> TerminalDigest {
        let outcome = lock.withLock { () -> Result<TerminalDigest, LumiError> in
            _sessionRequests.append(transcript)
            return self.outcome
        }
        return try outcome.get()
    }
}
