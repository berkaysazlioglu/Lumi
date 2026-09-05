import XCTest
@testable import LumiServices
import LumiKit

final class AgentHistoryServiceTests: XCTestCase {
    func testNestedClaudeAndCodexFixtures() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let c = root.appendingPathComponent("claude/projects/-repo")
        let x = root.appendingPathComponent("codex/sessions")
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: x, withIntermediateDirectories: true)
        try put("{\"type\":\"file-history-snapshot\"}\n{\"type\":\"user\",\"sessionId\":\"claude-1\",\"cwd\":\"/repo\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Build game\"}]}}", c.appendingPathComponent("a.jsonl"))
        try put("{\"type\":\"session_meta\",\"payload\":{\"id\":\"codex-1\",\"cwd\":\"/repo\"}}\n{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"content\":[{\"type\":\"input_text\",\"text\":\"Fix tests\"}]}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"Run suite\"}}", x.appendingPathComponent("b.jsonl"))
        let env = ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("claude").path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let entries = try await AgentHistoryService(home: root, environment: env).entries(projectPath: "/repo")
        XCTAssertEqual(Set(entries.map(\.sessionID)), ["claude-1", "codex-1"])
        XCTAssertEqual(entries.first { $0.sessionID == "claude-1" }?.title, "Build game")
        XCTAssertEqual(entries.first { $0.sessionID == "codex-1" }?.preview, "Run suite")
    }

    func testMalformedDuplicateAndUnsafeID() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let d = root.appendingPathComponent(".claude/projects/-repo")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try put("bad", d.appendingPathComponent("bad.jsonl"))
        for name in ["a", "b"] { try put("{\"sessionId\":\"same\",\"cwd\":\"/repo\",\"message\":{\"content\":\"x\"}}", d.appendingPathComponent(name + ".jsonl")) }
        let entries = try await AgentHistoryService(home: root, environment: [:]).entries(projectPath: "/repo")
        XCTAssertEqual(entries.filter { $0.sessionID == "same" }.count, 1)
        XCTAssertNil(AgentHistoryEntry(provider: .codex, sessionID: "bad id; rm", title: "x", updatedAt: .now, logPath: "/tmp/x").resumeCommand)
    }

    func testOversizedTranscriptKeepsTailMetadata() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let d = root.appendingPathComponent(".claude/projects/-repo")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let padding = String(repeating: "x", count: 700_000)
        let content = padding + "\n{\"type\":\"user\",\"sessionId\":\"tail\",\"cwd\":\"/repo\",\"message\":{\"content\":\"Latest prompt\"}}\n"
        try put(content, d.appendingPathComponent("tail.jsonl"))
        let entries = try await AgentHistoryService(home: root, environment: [:]).entries(projectPath: "/repo")
        XCTAssertEqual(entries.first?.preview, "Latest prompt")
    }

    func testEntryCarriesBranchModelCountAndRecentTurns() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent(".claude/projects/-repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"user","cwd":"/repo","gitBranch":"feature/history","sessionId":"rich","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#,
            #"{"type":"user","cwd":"/repo","gitBranch":"feature/history","sessionId":"rich","message":{"role":"user","content":"Agent History okunur olsun"}}"#,
            #"{"type":"assistant","cwd":"/repo","sessionId":"rich","message":{"role":"assistant","model":"claude-opus-4-1","content":[{"type":"tool_use","id":"t","name":"Read","input":{}}]}}"#,
            #"{"type":"user","cwd":"/repo","sessionId":"rich","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}"#,
            #"{"type":"assistant","cwd":"/repo","sessionId":"rich","message":{"role":"assistant","model":"claude-opus-4-1","content":[{"type":"text","text":"Kart eklendi"}]}}"#,
        ]
        try put(lines.joined(separator: "\n"), dir.appendingPathComponent("rich.jsonl"))

        let entries = try await AgentHistoryService(home: root, environment: [:]).entries(projectPath: "/repo")

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.gitBranch, "feature/history")
        XCTAssertEqual(entry.model, "claude-opus-4-1")
        XCTAssertEqual(entry.modelLabel, "opus-4-1")
        XCTAssertEqual(entry.messageCount, 2)
        XCTAssertEqual(entry.firstPrompt, "Agent History okunur olsun")
        XCTAssertEqual(entry.title, "Agent History okunur olsun")
        XCTAssertEqual(entry.recentTurns.map(\.role), [.user, .assistant])
        XCTAssertEqual(entry.preview, "Kart eklendi")
    }

    private func makeRoot() throws -> URL { let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }
    private func put(_ s: String, _ u: URL) throws { try Data(s.utf8).write(to: u) }
}
