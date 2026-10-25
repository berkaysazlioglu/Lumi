import Foundation
import LumiKit

public actor FakeAgentSessionTransferService: AgentSessionTransferring {
    public private(set) var exported: [(entry: AgentHistoryEntry, destination: URL)] = []
    public private(set) var imported: [(source: URL, projectPath: String)] = []
    public private(set) var archivedEntries: [AgentHistoryEntry] = []
    public private(set) var importedArchives: [(data: Data, projectPath: String)] = []
    public var archiveData = Data(#"{"format":"lumi-agent-session"}"#.utf8)
    public var failure: Error?
    public var importResult: AgentSessionImportResult

    public init(importResult: AgentSessionImportResult = AgentSessionImportResult(
        provider: .claude, sessionID: "imported", logPath: "/tmp/imported.jsonl", subagentCount: 0, didRenameSession: false
    )) {
        self.importResult = importResult
    }

    public func setFailure(_ value: Error?) { failure = value }
    public func setImportResult(_ value: AgentSessionImportResult) { importResult = value }

    public func exportSession(_ entry: AgentHistoryEntry, to destination: URL) async throws {
        if let failure { throw failure }
        exported.append((entry, destination))
    }

    public func importSession(from source: URL, projectPath: String) async throws -> AgentSessionImportResult {
        if let failure { throw failure }
        imported.append((source, projectPath))
        return importResult
    }

    public func exportArchive(_ entry: AgentHistoryEntry) async throws -> Data {
        if let failure { throw failure }
        archivedEntries.append(entry)
        return archiveData
    }

    public func importArchive(_ data: Data, projectPath: String) async throws -> AgentSessionImportResult {
        if let failure { throw failure }
        importedArchives.append((data, projectPath))
        return importResult
    }
}
