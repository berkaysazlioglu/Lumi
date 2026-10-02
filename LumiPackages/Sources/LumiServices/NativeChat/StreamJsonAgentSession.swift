import Foundation
import LumiKit

/// Bir chat oturumu: claude'u stream-json child olarak çalıştırır, çıktısını
/// journal'a katlar, kullanıcı mesajını stdin'e yazar (spec §D). PTY yok.
public actor StreamJsonAgentSession {
    private let sessionID: String
    private let repoPath: String
    private let environment: [String: String]
    /// Var olan konuşmayı sürdür (`--resume`) — yoksa `--session-id` ile yeni.
    private let resume: Bool
    /// Çağıranın ek bayrakları (orchestrator'ın system prompt'u, model…).
    private let extraArguments: [String]
    private let spawner: any StreamingProcessSpawning
    private let binaryLocator: any BinaryLocating

    private let journal = ChatJournal()
    private var handle: (any StreamingProcessHandle)?
    private var readTask: Task<Void, Never>?
    // id-anahtarlı: consumer (köprü task'i) iptal edince onTermination ile temizlenir
    // → uzun-yaşayan oturumda tekrar-abonelikler continuation biriktirmez (final review #3).
    private var snapshotContinuations: [UUID: AsyncStream<ChatJournalState>.Continuation] = [:]
    private var finished = false

    public init(sessionID: String, repoPath: String, environment: [String: String],
                resume: Bool = false, extraArguments: [String] = [],
                spawner: any StreamingProcessSpawning = LiveStreamingProcess(),
                binaryLocator: any BinaryLocating = SystemBinaryLocator()) {
        self.sessionID = sessionID
        self.repoPath = repoPath
        self.environment = environment
        self.resume = resume
        self.extraArguments = extraArguments
        self.spawner = spawner
        self.binaryLocator = binaryLocator
    }

    public func start() async {
        guard handle == nil else { return }
        let claude = await binaryLocator.locate("claude") ?? "claude"
        let args = Self.arguments(sessionID: sessionID, resume: resume, extra: extraArguments)
        let h = spawner.spawn(executable: claude, arguments: args,
                              currentDirectory: repoPath, environment: environment)
        handle = h
        readTask = Task { [weak self] in
            guard let self else { return }
            for await line in h.lines {
                if Task.isCancelled { break }
                await self.ingest(line)
            }
            await self.finishSnapshots()
        }
    }

    static func arguments(sessionID: String, resume: Bool, extra: [String]) -> [String] {
        ["-p", "--input-format", "stream-json", "--output-format", "stream-json",
         "--include-partial-messages", "--verbose",
         resume ? "--resume" : "--session-id", sessionID] + extra
    }

    private func ingest(_ line: String) {
        let snap = journal.reduce(StreamJsonEvent.decode(line))
        for c in snapshotContinuations.values { c.yield(snap) }
    }

    private func finishSnapshots() {
        for c in snapshotContinuations.values { c.finish() }
        snapshotContinuations.removeAll()
        finished = true
    }

    private func removeContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    public func send(_ text: String) async {
        let payload: [String: Any] = ["type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": text]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        handle?.write(json + "\n")
    }

    public func snapshots() -> AsyncStream<ChatJournalState> {
        AsyncStream { continuation in
            continuation.yield(journal.state)   // mevcut durum
            if finished {
                continuation.finish()
            } else {
                let id = UUID()
                snapshotContinuations[id] = continuation
                // Consumer iptal edince (köprü task cancel) actor'a dönüp temizle.
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeContinuation(id) }
                }
            }
        }
    }

    public func stop() async {
        readTask?.cancel()
        handle?.terminate()
        handle = nil
        finishSnapshots()
    }
}
