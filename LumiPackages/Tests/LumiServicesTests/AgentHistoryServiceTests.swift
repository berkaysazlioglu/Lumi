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

    private func makeRoot() throws -> URL { let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }
    private func put(_ s: String, _ u: URL) throws { try Data(s.utf8).write(to: u) }
}
