import LumiKit
@testable import LumiServices
import XCTest

final class AgentSubagentScannerTests: XCTestCase {
    func testScanReadsMetaCountsMessagesAndFallsBackToPrompt() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("abc.jsonl")
        try Data("{}".utf8).write(to: session)
        let dir = root.appendingPathComponent("abc/subagents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try put("""
        {"type":"user","message":{"role":"user","content":"Review the diff"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]}}
        """, dir.appendingPathComponent("agent-a1.jsonl"))
        try put("""
        {"agentType":"Explore","description":"Find explorer code","toolUseId":"t1","model":"sonnet"}
        """, dir.appendingPathComponent("agent-a1.meta.json"))
        try put("""
        {"type":"user","message":{"role":"user","content":"  Summarize tests  "}}
        """, dir.appendingPathComponent("agent-b2.jsonl"))
        try put("ignored", dir.appendingPathComponent("notes.txt"))

        let result = AgentSubagentScanner.scan(sessionLog: session)

        XCTAssertEqual(Set(result.map(\.id)), ["a1", "b2"])
        let first = result.first { $0.id == "a1" }
        XCTAssertEqual(first?.name, "Find explorer code")
        XCTAssertEqual(first?.kind, "Explore")
        XCTAssertEqual(first?.model, "sonnet")
        XCTAssertEqual(first?.messageCount, 3)
        let second = result.first { $0.id == "b2" }
        XCTAssertEqual(second?.name, "Summarize tests")
        XCTAssertNil(second?.kind)
        XCTAssertEqual(second?.messageCount, 1)
    }

    func testMissingDirectoryYieldsNoSubagents() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(AgentSubagentScanner.scan(sessionLog: root.appendingPathComponent("none.jsonl")), [])
    }

    private func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func put(_ value: String, _ url: URL) throws { try Data(value.utf8).write(to: url) }
}
