import Foundation
import LumiKit

/// Agent History oturumlarını `.lumisession.json` paketine yazar ve paketten
/// sağlayıcı dizinine geri kurar (karar 52).
///
/// Dışa aktarma: ana transkript + Claude alt ajan transkriptleri tam okunur,
/// `AgentSessionSanitizer` kişisel kayıtları düşürür. Codex kayıtları olduğu
/// gibi taşınır (kişisel ek kayıt içermez; yalnız yollar).
///
/// İçe aktarma: hedef proje köküne göre yollar yeniden yazılır, aynı kimlikte
/// oturum varsa yeni UUID üretilir, dosya sağlayıcının kendi konumuna yazılır
/// (Claude `projects/<encoded>/<id>.jsonl`, Codex `sessions/yyyy/MM/dd/<ad>`).
public actor AgentSessionTransferService: AgentSessionTransferring {
    static let maxFileBytes = 64 * 1024 * 1024
    private let roots: AgentDataRoots
    private let now: @Sendable () -> Date

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        roots = AgentDataRoots(home: home, environment: environment)
        self.now = now
    }

    // MARK: - Export

    public func exportSession(_ entry: AgentHistoryEntry, to destination: URL) async throws {
        let log = URL(fileURLWithPath: entry.logPath)
        let records = try readRecords(log)
        let isClaude = entry.provider == .claude
        let archive = AgentSessionArchive(
            provider: entry.provider,
            sessionID: entry.sessionID,
            cwd: entry.cwd,
            title: entry.title,
            fileName: log.lastPathComponent,
            records: isClaude ? AgentSessionSanitizer.sanitize(records) : records,
            subagents: isClaude ? try exportSubagents(entry.subagents) : []
        )
        do {
            try archive.encode().write(to: destination, options: .atomic)
        } catch {
            throw LumiError.sessionTransferFailed(detail: "Could not write \(destination.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func exportSubagents(_ subagents: [AgentHistorySubagent]) throws -> [AgentSessionArchive.Subagent] {
        try subagents.map { subagent in
            let log = URL(fileURLWithPath: subagent.logPath)
            let meta = FileManager.default.contents(atPath: log.deletingPathExtension().appendingPathExtension("meta.json").path)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return AgentSessionArchive.Subagent(
                id: subagent.id, meta: meta, records: AgentSessionSanitizer.sanitize(try readRecords(log))
            )
        }
    }

    // MARK: - Import

    public func importSession(from source: URL, projectPath: String) async throws -> AgentSessionImportResult {
        let archive = try AgentSessionArchive.decode(readData(source))
        let project = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let target = try plan(archive, project: project)
        let rewriter = AgentSessionRewriter(replacements: replacements(archive, project: project, target: target))
        try createDirectory(target.directory)
        try writeRecords(rewriter.rewrite(archive.records), to: target.file)
        try importSubagents(archive.subagents, rewriter: rewriter, target: target)
        return AgentSessionImportResult(
            provider: archive.provider, sessionID: target.sessionID, logPath: target.file.path,
            subagentCount: archive.subagents.count, didRenameSession: target.sessionID != archive.sessionID
        )
    }

    private struct Target {
        let sessionID: String
        let directory: URL
        let file: URL
    }

    private func plan(_ archive: AgentSessionArchive, project: String) throws -> Target {
        let directory: URL
        let name: (String) -> String
        switch archive.provider {
        case .claude:
            directory = roots.claudeProjectDirectory(project)
            name = { "\($0).jsonl" }
        case .codex:
            directory = roots.codexSessions.appendingPathComponent(codexDatePath(archive))
            let original = archive.fileName
            name = { id in
                original.contains(archive.sessionID)
                    ? original.replacingOccurrences(of: archive.sessionID, with: id)
                    : "rollout-\(id).jsonl"
            }
        }
        let original = directory.appendingPathComponent(name(archive.sessionID))
        guard FileManager.default.fileExists(atPath: original.path) else {
            return Target(sessionID: archive.sessionID, directory: directory, file: original)
        }
        let renamed = UUID().uuidString.lowercased()
        return Target(sessionID: renamed, directory: directory, file: directory.appendingPathComponent(name(renamed)))
    }

    private func replacements(_ archive: AgentSessionArchive, project: String, target: Target) -> [AgentSessionRewriter.Replacement] {
        var result: [AgentSessionRewriter.Replacement] = []
        if let cwd = archive.cwd, !cwd.isEmpty, cwd != "/", cwd != project {
            result.append(.init(from: cwd, to: project, requiresPathBoundary: true))
        }
        if target.sessionID != archive.sessionID {
            result.append(.init(from: archive.sessionID, to: target.sessionID, requiresPathBoundary: false))
        }
        return result
    }

    /// Codex `sessions/yyyy/MM/dd`: `session_meta.payload.timestamp`, yoksa bugün.
    private func codexDatePath(_ archive: AgentSessionArchive) -> String {
        let meta = archive.records.first { $0["type"] as? String == "session_meta" }
        let stamp = ((meta?["payload"] as? [String: Any])?["timestamp"] as? String)
            .flatMap(Self.parseISODate)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: stamp ?? now())
    }

    private func importSubagents(_ subagents: [AgentSessionArchive.Subagent], rewriter: AgentSessionRewriter, target: Target) throws {
        guard !subagents.isEmpty else { return }
        let directory = target.file.deletingPathExtension().appendingPathComponent("subagents")
        try createDirectory(directory)
        for subagent in subagents {
            let log = directory.appendingPathComponent("agent-\(subagent.id).jsonl")
            try writeRecords(rewriter.rewrite(subagent.records), to: log)
            if let meta = rewriter.rewrite(subagent.meta) {
                let data = try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .withoutEscapingSlashes])
                try write(data, to: log.deletingPathExtension().appendingPathExtension("meta.json"))
            }
        }
    }

    // MARK: - I/O

    private func readData(_ url: URL) throws -> Data {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) else {
            throw LumiError.sessionTransferFailed(detail: "Cannot read \(url.lastPathComponent).")
        }
        guard size <= Self.maxFileBytes else {
            throw LumiError.sessionTransferFailed(detail: "\(url.lastPathComponent) exceeds the 64 MB limit.")
        }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw LumiError.sessionTransferFailed(detail: "Cannot read \(url.lastPathComponent).")
        }
        return data
    }

    private func readRecords(_ url: URL) throws -> [[String: Any]] {
        let records = try readData(url)
            .split(separator: 10, omittingEmptySubsequences: true)
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
        guard !records.isEmpty else {
            throw LumiError.sessionTransferFailed(detail: "\(url.lastPathComponent) has no readable records.")
        }
        return records
    }

    private func writeRecords(_ records: [[String: Any]], to url: URL) throws {
        var data = Data()
        for record in records {
            data.append(try JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes]))
            data.append(10)
        }
        try write(data, to: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw LumiError.sessionTransferFailed(detail: "Could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw LumiError.sessionTransferFailed(detail: "Could not create \(url.path): \(error.localizedDescription)")
        }
    }
}

extension AgentSessionTransferService {
    static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
