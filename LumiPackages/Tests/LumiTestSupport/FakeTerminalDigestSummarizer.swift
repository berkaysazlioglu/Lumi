import Foundation
import LumiKit

/// Test için sahte özetleyici (karar 114 Faz 4): sabit özet ya da hata döner,
/// çağrıları kaydeder.
public final class FakeTerminalDigestSummarizer: TerminalDigestSummarizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private var _sessionRequests: [String] = []
    private var outcome: Result<TerminalDigest, LumiError> = .success(TerminalDigest(summary: "özet", needsUser: false))
    private var isHeld = false
    private var heldCalls: [CheckedContinuation<Void, Never>] = []
    private var _completedCount = 0

    public init() {}

    /// `summarize` çağrılarının mesajları.
    public var requests: [String] { lock.withLock { _requests } }
    /// `summarizeSession` çağrılarının transkriptleri.
    public var sessionRequests: [String] { lock.withLock { _sessionRequests } }

    public func stub(_ outcome: Result<TerminalDigest, LumiError>) { lock.withLock { self.outcome = outcome } }
    /// Biten `summarize` çağrılarının sayısı.
    public var completedCount: Int { lock.withLock { _completedCount } }

    /// Sıra testleri için: `release()` çağrılana dek `summarize` cevap vermez.
    /// Süreye dayanan gecikmeden farkı, yavaş runner'da da sıranın kesin olması.
    public func hold() { lock.withLock { isHeld = true } }

    public func release() {
        let calls = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isHeld = false
            defer { heldCalls = [] }
            return heldCalls
        }
        calls.forEach { $0.resume() }
    }

    public func summarize(agentMessage: String, terminalTitle: String) async throws -> TerminalDigest {
        let outcome = lock.withLock { () -> Result<TerminalDigest, LumiError> in
            _requests.append(agentMessage)
            return self.outcome
        }
        await withCheckedContinuation { (call: CheckedContinuation<Void, Never>) in
            let shouldWait = lock.withLock { () -> Bool in
                if isHeld { heldCalls.append(call) }
                return isHeld
            }
            if !shouldWait { call.resume() }
        }
        lock.withLock { _completedCount += 1 }
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
