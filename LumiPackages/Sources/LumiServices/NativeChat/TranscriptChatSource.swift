import Foundation
import LumiKit

/// Claude transcript JSONL'ini polling ile tail edip chat olayları yayar
/// (orca `transcript-watch`/`transcript-tail-boundary` Faz 1 alt kümesi).
/// Değişmez durum (hepsi `let`) → `struct` + otomatik `Sendable`; aktör izolasyonu
/// gerekmez (dosya okuma saf, self mutasyonu yok).
public struct TranscriptChatSource: ChatTranscriptSourcing {
    private let home: URL
    private let pollInterval: Duration
    private let decoder = ClaudeTranscriptChatDecoder()

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                pollInterval: Duration = .milliseconds(500)) {
        self.home = home
        self.pollInterval = pollInterval
    }

    public func stream(sessionID: String, repoPath: String) -> AsyncStream<ChatMirrorEvent> {
        AsyncStream { continuation in
            let task = Task { [pollInterval] in
                let file = Self.transcriptURL(home: self.home, sessionID: sessionID, repoPath: repoPath)
                var offset: UInt64 = 0
                var index = 0
                var sentSnapshot = false
                while !Task.isCancelled {
                    let (messages, newOffset, newIndex) = self.readAppended(file, from: offset, index: index)
                    offset = newOffset
                    index = newIndex
                    if !sentSnapshot {
                        continuation.yield(.snapshot(messages))
                        sentSnapshot = true
                    } else if !messages.isEmpty {
                        continuation.yield(.append(messages))
                    }
                    try? await Task.sleep(for: pollInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Transkriptin o anki tamamı — tek okuma, tail yok (karar 103: resume
    /// edilen orchestrator konuşmasının geçmişi). Dosya yoksa boş.
    public func messages(sessionID: String, repoPath: String) -> [ChatMessage] {
        let file = Self.transcriptURL(home: home, sessionID: sessionID, repoPath: repoPath)
        return readAppended(file, from: 0, index: 0).0
    }

    /// Kuyruk okuması: büyük transkriptin yalnız son `maxBytes`'ı çözülür
    /// (ortadan başlayan ilk yarım satır JSON olmadığı için kendiliğinden atlanır).
    public func tailMessages(sessionID: String, repoPath: String, maxBytes: Int = Self.tailBytes) -> [ChatMessage] {
        let file = Self.transcriptURL(home: home, sessionID: sessionID, repoPath: repoPath)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        return readAppended(file, from: offset, index: 0).0
    }

    /// `read_terminal` için yeterli kuyruk (son birkaç düzine mesaj).
    public static let tailBytes = 2 * 1024 * 1024

    /// `<home>/.claude/projects/<encoded-cwd>/<sid>.jsonl`. Klasör adı Claude'un
    /// kuralıyla kodlanır: cwd'deki alfanümerik OLMAYAN her karakter `-` olur
    /// (`_`, `.` dahil). Yalnız `/`→`-` yapmak alt çizgili/nokta içeren repo'da
    /// (ör. `sandout_word-puzzle`) yanlış klasöre bakıp transcript'i kaçırırdı —
    /// tek kaynak `AgentDataRoots.encodedProjectName`.
    static func transcriptURL(home: URL, sessionID: String, repoPath: String) -> URL {
        let encoded = AgentDataRoots.encodedProjectName(repoPath)
        return home.appendingPathComponent(".claude/projects/\(encoded)/\(sessionID).jsonl")
    }

    /// Offset'ten itibaren tam satırları okuyup decode eder; yeni offset + index döner.
    private func readAppended(_ file: URL, from offset: UInt64, index: Int) -> ([ChatMessage], UInt64, Int) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return ([], offset, index) }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return ([], offset, index) }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return ([], offset, index) }
        // Son newline'a kadar tam satırlar; yarım son satır bir sonraki poll'a kalsın.
        guard let lastNL = data.lastIndex(of: 0x0A) else { return ([], offset, index) }
        let complete = data[..<data.index(after: lastNL)]
        var messages: [ChatMessage] = []
        var idx = index
        for lineData in complete.split(separator: 0x0A) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(lineData)),
                  let record = obj as? [String: Any] else { idx += 1; continue }
            if let msg = decoder.decode(record, index: idx) { messages.append(msg) }
            idx += 1
        }
        return (messages, offset + UInt64(complete.count), idx)
    }
}

extension TranscriptChatSource: TerminalTranscriptReading {
    /// Dosya okuması main actor'ı tutmasın diye ayrık görevde koşar.
    public func recentClaudeMessages(sessionID: String, cwd: String) async -> [ChatMessage] {
        await Task.detached(priority: .utility) {
            self.tailMessages(sessionID: sessionID, repoPath: cwd)
        }.value
    }
}
