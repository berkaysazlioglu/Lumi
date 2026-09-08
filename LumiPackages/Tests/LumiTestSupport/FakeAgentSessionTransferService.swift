import Foundation
import LumiKit

public actor FakeAgentSessionTransferService: AgentSessionTransferring {
    public private(set) var exported: [(entry: AgentHistoryEntry, destination: URL)] = []
    public private(set) var imported: [(source: URL, projectPath: String)] = []
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
}
