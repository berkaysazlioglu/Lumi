import LumiKit
@testable import LumiServices
import XCTest

final class AgentHistoryServiceDeleteTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    func testDeletesClaudeLogAndSidecarDirectory() async throws {
        let dir = home.appendingPathComponent(".claude/projects/-repo")
        let sidecar = dir.appendingPathComponent("s1/subagents")
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("s1.jsonl")
        try Data("{}".utf8).write(to: log)
        try Data("{}".utf8).write(to: sidecar.appendingPathComponent("agent-a.jsonl"))
        let other = dir.appendingPathComponent("s2.jsonl")
        try Data("{}".utf8).write(to: other)
        let service = AgentHistoryService(home: home, environment: [:], usesTrash: false)

        try await service.deleteSession(AgentHistoryEntry(provider: .claude, sessionID: "s1", title: "t", updatedAt: .now, logPath: log.path))

        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("s1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "komşu oturuma dokunulmaz")
    }

    func testDeletesCodexLogOnly() async throws {
        let dir = home.appendingPathComponent(".codex/sessions/2026/01/01")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("rollout-x.jsonl")
        try Data("{}".utf8).write(to: log)
        let service = AgentHistoryService(home: home, environment: [:], usesTrash: false)
        try await service.deleteSession(AgentHistoryEntry(provider: .codex, sessionID: "x", title: "t", updatedAt: .now, logPath: log.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testRefusesPathsOutsideProviderRoot() async throws {
        let stray = home.appendingPathComponent("important.jsonl")
        try Data("{}".utf8).write(to: stray)
        let service = AgentHistoryService(home: home, environment: [:], usesTrash: false)
        for provider in AgentProvider.allCases {
            do {
                try await service.deleteSession(AgentHistoryEntry(provider: provider, sessionID: "x", title: "t", updatedAt: .now, logPath: stray.path))
                XCTFail("expected refusal for \(provider)")
            } catch let error as LumiError {
                guard case .sessionTransferFailed = error else { return XCTFail("\(error)") }
            }
        }
        // Kök altında ama .jsonl değil (ör. meta.json) — reddedilir.
        let dir = home.appendingPathComponent(".claude/projects/-repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let meta = dir.appendingPathComponent("x.meta.json")
        try Data("{}".utf8).write(to: meta)
        await XCTAssertThrowsErrorAsync(try await service.deleteSession(
            AgentHistoryEntry(provider: .claude, sessionID: "x", title: "t", updatedAt: .now, logPath: meta.path)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: meta.path))
    }

    func testMissingLogIsReportedNotIgnored() async {
        let service = AgentHistoryService(home: home, environment: [:], usesTrash: false)
        let ghost = home.appendingPathComponent(".claude/projects/-repo/ghost.jsonl")
        await XCTAssertThrowsErrorAsync(try await service.deleteSession(
            AgentHistoryEntry(provider: .claude, sessionID: "ghost", title: "t", updatedAt: .now, logPath: ghost.path)))
    }
}

private func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {}
}
