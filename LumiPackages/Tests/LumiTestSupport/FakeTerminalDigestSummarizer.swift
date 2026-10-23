import Foundation
import LumiKit

/// Test için sahte özetleyici (karar 114 Faz 4): sabit özet ya da hata döner,
/// çağrıları kaydeder.
public final class FakeTerminalDigestSummarizer: TerminalDigestSummarizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private var _sessionRequests: [String] = []
    private var outcome: Result<TerminalDigest, LumiError> = .success(TerminalDigest(summary: "özet", needsUser: false))
    private var delay: Duration = .zero

    public init() {}

    /// `summarize` çağrılarının mesajları.
    public var requests: [String] { lock.withLock { _requests } }
    /// `summarizeSession` çağrılarının transkriptleri.
    public var sessionRequests: [String] { lock.withLock { _sessionRequests } }

    public func stub(_ outcome: Result<TerminalDigest, LumiError>) { lock.withLock { self.outcome = outcome } }
    /// Yavaş haiku (sıra/yarış testleri): `summarize` cevabı bu kadar gecikir.
    public func setDelay(_ delay: Duration) { lock.withLock { self.delay = delay } }

    public func summarize(agentMessage: String, terminalTitle: String) async throws -> TerminalDigest {
        let outcome = lock.withLock { () -> Result<TerminalDigest, LumiError> in
            _requests.append(agentMessage)
            return self.outcome
        }
        let delay = lock.withLock { self.delay }
        if delay > .zero { try? await Task.sleep(for: delay) }
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
