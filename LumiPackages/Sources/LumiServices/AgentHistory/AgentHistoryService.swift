import Foundation
import LumiKit

public actor AgentHistoryService: AgentHistoryReading {
    private let home: URL
    private let environment: [String: String]
    private let maxFiles = 2_000
    private let maxEntries = 200
    private let maxEnumeratedItems = 20_000
    private let sampleBytes = 256 * 1024

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
        guard let handle = try? FileHandle(forReadingFrom: candidate.url) else { return nil }
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
        let sampled = headRecords + tailRecords
        let metadata = sampled.first { record in
            candidate.provider == .claude ? record["cwd"] is String : record["type"] as? String == "session_meta"
        }
        let fields = candidate.provider == .claude ? metadata : metadata?["payload"] as? [String: Any]
        guard let cwd = fields?["cwd"] as? String,
              URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath().path == project else { return nil }
        let sessionID = fields?[candidate.provider == .claude ? "sessionId" : "id"] as? String
            ?? candidate.url.deletingPathExtension().lastPathComponent
        let title = sampled.compactMap { text($0, userOnly: true) }.first ?? "Untitled session"
        let preview = sampled.reversed()
            .compactMap { text($0, userOnly: false) }.first
        return AgentHistoryEntry(
            provider: candidate.provider, sessionID: sessionID,
            title: String(title.prefix(160)), preview: preview.map { String($0.prefix(2_000)) },
            updatedAt: candidate.date, cwd: cwd, logPath: candidate.url.path
        )
    }

    private func records(_ data: Data, dropFirst: Bool, dropLast: Bool) -> [[String: Any]] {
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if dropFirst && !lines.isEmpty { lines.removeFirst() }
        if dropLast && !lines.isEmpty { lines.removeLast() }
        return lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    }

    private func text(_ record: [String: Any], userOnly: Bool) -> String? {
        let kind = record["type"] as? String
        let message = record["message"] as? [String: Any]
        let payload = record["payload"] as? [String: Any]
        let content: Any?
        if kind == "user" || (!userOnly && kind == "assistant") {
            content = message?["content"]
        } else if kind == "event_msg", payload?["type"] as? String == "user_message" {
            content = payload?["message"]
        } else if kind == "response_item", payload?["type"] as? String == "message",
                  !userOnly || payload?["role"] as? String == "user" {
            content = payload?["content"]
        } else { return nil }
        let text: String
        if let string = content as? String { text = string }
        else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { block -> String? in
                guard let type = block["type"] as? String, ["text", "input_text", "output_text"].contains(type) else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        } else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<environment_context>"),
              !trimmed.hasPrefix("# AGENTS.md instructions"), !trimmed.hasPrefix("<system-reminder>") else { return nil }
        return trimmed
    }
}
