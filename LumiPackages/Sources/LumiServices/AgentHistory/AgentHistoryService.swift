import Foundation
import LumiKit

public actor AgentHistoryService: AgentHistoryReading {
    private let home: URL
    private let environment: [String: String]
    private let maxFiles = 2_000
    private let maxEntries = 200
    private let maxEnumeratedItems = 20_000
    private let sampleBytes = 256 * 1024
    private let maxRecentTurns = 3
    private let maxTurnPreviewLength = 400
    private let maxTitleLength = 160
    private let maxFirstPromptLength = 2_000

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.home = home
        self.environment = environment
    }

    public func entries(projectPath: String) async throws -> [AgentHistoryEntry] {
        let project = URL(fileURLWithPath: projectPath).standardizedFileURL.resolvingSymlinksInPath().path
        let claude = directory("CLAUDE_CONFIG_DIR", fallback: ".claude")
        let codex = directory("CODEX_HOME", fallback: ".codex")
        let encoded = projectPath.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
        let roots: [(URL, AgentProvider)] = [
            (claude.appendingPathComponent("projects/" + encoded), .claude),
            (codex.appendingPathComponent("sessions"), .codex),
        ]
        let candidates = try roots.flatMap { try files(in: $0.0, provider: $0.1) }
            .sorted { $0.date > $1.date }
        var result: [AgentHistoryEntry] = []
        var seen: Set<String> = []
        for candidate in candidates.prefix(maxFiles) {
            try Task.checkCancellation()
            guard let entry = read(candidate, project: project), seen.insert(entry.id).inserted else { continue }
            result.append(entry)
            if result.count == maxEntries { break }
        }
        return result
    }

    private struct Candidate {
        let url: URL
        let provider: AgentProvider
        let date: Date
    }

    private func directory(_ key: String, fallback: String) -> URL {
        guard let path = environment[key], !path.isEmpty else { return home.appendingPathComponent(fallback) }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private func files(in root: URL, provider: AgentProvider) throws -> [Candidate] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [Candidate] = []
        var count = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            count += 1
            if count > maxEnumeratedItems { break }
            guard let info = try? url.resourceValues(forKeys: keys) else { continue }
            if info.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            // Claude subagents are separate logs, not resumable top-level sessions.
            if provider == .claude && info.isRegularFile != true { enumerator.skipDescendants(); continue }
            guard info.isRegularFile == true, url.pathExtension == "jsonl" else { continue }
            result.append(Candidate(url: url, provider: provider, date: info.contentModificationDate ?? .distantPast))
        }
        return result
    }

    private func read(_ candidate: Candidate, project: String) -> AgentHistoryEntry? {
        guard let sampled = sample(candidate.url) else { return nil }
        let transcript = AgentTranscriptParser(provider: candidate.provider).parse(sampled)
        guard let cwd = transcript.cwd,
              URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath().path == project else { return nil }
        let sessionID = transcript.sessionID ?? candidate.url.deletingPathExtension().lastPathComponent
        let recent = transcript.turns.suffix(maxRecentTurns).map { $0.truncated(to: maxTurnPreviewLength) }
        return AgentHistoryEntry(
            provider: candidate.provider,
            sessionID: sessionID,
            title: String(title(transcript).prefix(maxTitleLength)),
            preview: recent.last.map(\.text),
            updatedAt: candidate.date,
            cwd: cwd,
            logPath: candidate.url.path,
            gitBranch: transcript.gitBranch,
            model: transcript.model,
            messageCount: transcript.messageCount,
            firstPrompt: transcript.firstPrompt.map { String($0.prefix(maxFirstPromptLength)) },
            recentTurns: Array(recent),
            subagents: candidate.provider == .claude ? AgentSubagentScanner.scan(sessionLog: candidate.url) : []
        )
    }

    /// Başlık ilk kullanıcı istemidir; transkriptin başı örnekleme dışında
    /// kaldıysa (çok büyük dosya) ilk konuşma turuna düşer.
    private func title(_ transcript: AgentTranscriptParser.Transcript) -> String {
        transcript.firstPrompt ?? transcript.turns.first?.text ?? "Untitled session"
    }

    /// Dosyanın baş ve son `sampleBytes`'ını okuyup JSON satırlarına ayırır.
    /// Kesilmiş ilk/son satır atılır — yarım JSON ayrıştırılamaz zaten.
    private func sample(_ url: URL) -> [[String: Any]]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), (try? handle.seek(toOffset: 0)) != nil,
              let head = try? handle.read(upToCount: sampleBytes) else { return nil }
        let headRecords = records(head, dropFirst: false, dropLast: size > UInt64(head.count))
        var tailRecords: [[String: Any]] = []
        if size > UInt64(sampleBytes),
           (try? handle.seek(toOffset: max(UInt64(sampleBytes), size - min(size, UInt64(sampleBytes))))) != nil,
           let tail = try? handle.read(upToCount: sampleBytes) {
            tailRecords = records(tail, dropFirst: true, dropLast: false)
        }
        return headRecords + tailRecords
    }

    private func records(_ data: Data, dropFirst: Bool, dropLast: Bool) -> [[String: Any]] {
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if dropFirst && !lines.isEmpty { lines.removeFirst() }
        if dropLast && !lines.isEmpty { lines.removeLast() }
        return lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    }
}
