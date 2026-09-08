import LumiKit
@testable import LumiServices
import XCTest

final class AgentSessionTransferServiceTests: XCTestCase {
    private var root: URL!
    private var sourceHome: URL!
    private var targetHome: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        sourceHome = root.appendingPathComponent("source-home")
        targetHome = root.appendingPathComponent("target-home")
        try FileManager.default.createDirectory(at: sourceHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetHome, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testClaudeExportThenImportRewritesPathsAndCopiesSubagents() async throws {
        let sourceProject = "/Users/alice/wkspaces/Lumi"
        let entry = try writeClaudeSession(home: sourceHome, project: sourceProject, id: "s1", subagents: ["a1"])
        let package = root.appendingPathComponent("s1.lumisession.json")
        let source = AgentSessionTransferService(home: sourceHome, environment: [:])
        try await source.exportSession(entry, to: package)

        let exported = try XCTUnwrap(String(data: Data(contentsOf: package), encoding: .utf8))
        XCTAssertFalse(exported.contains("alice@example.com"), "session_context ayıklanır")
        XCTAssertFalse(exported.contains("totalCostUSD"))
        XCTAssertTrue(exported.contains("Fix the bug"))

        let targetProject = "/Users/bob/code/Lumi"
        let target = AgentSessionTransferService(home: targetHome, environment: [:])
        let result = try await target.importSession(from: package, projectPath: targetProject)

        XCTAssertEqual(result.sessionID, "s1")
        XCTAssertFalse(result.didRenameSession)
        XCTAssertEqual(result.subagentCount, 1)
        let expectedLog = targetHome.appendingPathComponent(".claude/projects/-Users-bob-code-Lumi/s1.jsonl")
        XCTAssertEqual(result.logPath, expectedLog.path)
        let imported = try String(contentsOf: expectedLog, encoding: .utf8)
        XCTAssertTrue(imported.contains("\"cwd\":\"/Users/bob/code/Lumi\""))
        XCTAssertTrue(imported.contains("/Users/bob/code/Lumi/README.md"))
        XCTAssertFalse(imported.contains("/Users/alice"))
        let subagentLog = targetHome.appendingPathComponent(".claude/projects/-Users-bob-code-Lumi/s1/subagents/agent-a1.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: subagentLog.path))
        let meta = targetHome.appendingPathComponent(".claude/projects/-Users-bob-code-Lumi/s1/subagents/agent-a1.meta.json")
        XCTAssertTrue(try String(contentsOf: meta, encoding: .utf8).contains("general-purpose"))

        // İçe alınan oturum Agent History'de hedef proje altında listelenir.
        let history = AgentHistoryService(home: targetHome, environment: [:])
        let entries = try await history.entries(projectPath: targetProject)
        XCTAssertEqual(entries.map(\.sessionID), ["s1"])
        XCTAssertEqual(entries.first?.subagents.map(\.id), ["a1"])
    }

    func testImportRenamesSessionWhenIDAlreadyExists() async throws {
        let project = "/Users/alice/wkspaces/Lumi"
        let entry = try writeClaudeSession(home: sourceHome, project: project, id: "dup", subagents: [])
        let package = root.appendingPathComponent("dup.lumisession.json")
        let service = AgentSessionTransferService(home: sourceHome, environment: [:])
        try await service.exportSession(entry, to: package)

        let result = try await service.importSession(from: package, projectPath: project)

        XCTAssertTrue(result.didRenameSession)
        XCTAssertNotEqual(result.sessionID, "dup")
        let imported = try String(contentsOf: URL(fileURLWithPath: result.logPath), encoding: .utf8)
        XCTAssertTrue(imported.contains("\"sessionId\":\"\(result.sessionID)\""))
        XCTAssertFalse(imported.contains("\"sessionId\":\"dup\""))
    }

    func testCodexImportLandsInDatedSessionsFolder() async throws {
        let sessions = sourceHome.appendingPathComponent(".codex/sessions/2026/03/06")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let log = sessions.appendingPathComponent("rollout-2026-03-06T14-19-37-c0dex.jsonl")
        try Data("""
        {"timestamp":"2026-03-06T11:27:30.273Z","type":"session_meta","payload":{"id":"c0dex","timestamp":"2026-03-06T11:19:37.166Z","cwd":"/Users/alice/proj"}}
        {"timestamp":"2026-03-06T11:27:31.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}

        """.utf8).write(to: log)
        let entry = AgentHistoryEntry(provider: .codex, sessionID: "c0dex", title: "hello", updatedAt: .now,
                                      cwd: "/Users/alice/proj", logPath: log.path)
        let package = root.appendingPathComponent("codex.lumisession.json")
        try await AgentSessionTransferService(home: sourceHome, environment: [:]).exportSession(entry, to: package)

        let result = try await AgentSessionTransferService(home: targetHome, environment: [:])
            .importSession(from: package, projectPath: "/Users/bob/proj")

        XCTAssertEqual(result.provider, .codex)
        XCTAssertEqual(result.logPath, targetHome.appendingPathComponent(
            ".codex/sessions/2026/03/06/rollout-2026-03-06T14-19-37-c0dex.jsonl").path)
        XCTAssertTrue(try String(contentsOf: URL(fileURLWithPath: result.logPath), encoding: .utf8).contains("\"cwd\":\"/Users/bob/proj\""))
    }

    func testImportRejectsNonPackageFile() async throws {
        let bogus = root.appendingPathComponent("bogus.json")
        try Data("{\"hello\":1}".utf8).write(to: bogus)
        let service = AgentSessionTransferService(home: targetHome, environment: [:])
        do {
            _ = try await service.importSession(from: bogus, projectPath: "/p")
            XCTFail("expected failure")
        } catch let error as LumiError {
            guard case .sessionTransferFailed = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetHome.appendingPathComponent(".claude").path))
    }

    // MARK: - Fixtures

    private func writeClaudeSession(home: URL, project: String, id: String, subagents: [String]) throws -> AgentHistoryEntry {
        let encoded = AgentDataRoots.encodedProjectName(project)
        let dir = home.appendingPathComponent(".claude/projects/\(encoded)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("\(id).jsonl")
        try Data("""
        {"type":"user","uuid":"u1","parentUuid":null,"sessionId":"\(id)","cwd":"\(project)","message":{"role":"user","content":"Fix the bug"}}
        {"type":"attachment","uuid":"a1","parentUuid":"u1","sessionId":"\(id)","cwd":"\(project)","attachment":{"type":"session_context","context":{"userEmail":"alice@example.com"}}}
        {"type":"assistant","uuid":"s1","parentUuid":"a1","sessionId":"\(id)","cwd":"\(project)","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"\(project)/README.md"}}]}}
        {"type":"cost-state","sessionId":"\(id)","totalCostUSD":2.5}

        """.utf8).write(to: log)
        var models: [AgentHistorySubagent] = []
        if !subagents.isEmpty {
            let subDir = dir.appendingPathComponent("\(id)/subagents")
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            for sub in subagents {
                let subLog = subDir.appendingPathComponent("agent-\(sub).jsonl")
                try Data("""
                {"type":"user","uuid":"x1","parentUuid":null,"isSidechain":true,"agentId":"\(sub)","sessionId":"\(id)","cwd":"\(project)","message":{"role":"user","content":"Inspect \(project)/Sources"}}

                """.utf8).write(to: subLog)
                try Data(#"{"agentType":"general-purpose","description":"Inspect","model":"sonnet"}"#.utf8)
                    .write(to: subDir.appendingPathComponent("agent-\(sub).meta.json"))
                models.append(AgentHistorySubagent(id: sub, name: "Inspect", logPath: subLog.path))
            }
        }
        return AgentHistoryEntry(provider: .claude, sessionID: id, title: "Fix the bug", updatedAt: .now,
                                 cwd: project, logPath: log.path, subagents: models)
    }
}
