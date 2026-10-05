import Foundation
import LumiKit

/// Test için sahte orchestrator (karar 114). Her `start` yeni bir akış açar;
/// test `emit(_:)` ile journal durumu yayar, `finish()` ile süreç çıkışını
/// taklit eder. Çağrılar biriktirilir.
public final class FakeOrchestratorService: OrchestratorServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var _launches: [OrchestratorLaunch] = []
    private var _sent: [String] = []
    private var _stopCount = 0
    private var continuation: AsyncStream<ChatJournalState>.Continuation?
    private var history: [ChatMessage] = []
    private var startError: LumiError?

    public init() {}

    public var launches: [OrchestratorLaunch] { lock.withLock { _launches } }
    public var sent: [String] { lock.withLock { _sent } }
    public var stopCount: Int { lock.withLock { _stopCount } }

    /// Sonraki `start`'ların döndüreceği geçmiş.
    public func stubHistory(_ messages: [ChatMessage]) { lock.withLock { history = messages } }
    /// Sonraki `start` bu hatayla düşer (nil = başarı).
    public func stubStartError(_ error: LumiError?) { lock.withLock { startError = error } }

    public func emit(_ state: ChatJournalState) {
        _ = lock.withLock { continuation }?.yield(state)
    }

    /// Sürecin kendiliğinden çıkışı.
    public func finish() {
        lock.withLock { continuation }?.finish()
    }

    public func start(_ launch: OrchestratorLaunch) async throws -> OrchestratorRun {
        let (error, messages) = lock.withLock { (startError, history) }
        if let error { throw error }
        let (stream, continuation) = AsyncStream.makeStream(of: ChatJournalState.self)
        lock.withLock {
            self.continuation?.finish()
            self.continuation = continuation
            _launches.append(launch)
        }
        return OrchestratorRun(history: messages, updates: stream)
    }

    public func send(_ text: String) async {
        lock.withLock { _sent.append(text) }
    }

    public func stop() async {
        lock.withLock {
            _stopCount += 1
            continuation?.finish()
            continuation = nil
        }
    }
}
