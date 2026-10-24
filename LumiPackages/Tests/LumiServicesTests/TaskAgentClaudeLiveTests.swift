import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Gerçek Claude Code'un task-ajanı MCP sunucusuna bağlanıp
/// `submit_for_review`'u çağırdığını doğrular (karar 137, Faz 3). Yalnız
/// `LUMI_TASKS_AGENT_E2E=1` iken koşar — gerçek `claude` çağırır, kota harcar.
///
///     LUMI_TASKS_AGENT_E2E=1 swift test --filter TaskAgentClaudeLiveTests
final class TaskAgentClaudeLiveTests: XCTestCase {
    func testClaudeCallsSubmitForReviewThroughTheMCPConfig() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_TASKS_AGENT_E2E"] == "1" else {
            throw XCTSkip("LUMI_TASKS_AGENT_E2E not set")
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumi-agent-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let server = TaskAgentMCPServer(directory: directory.appendingPathComponent("mcp"))
        let box = Box()
        let session = try await server.register(details: "E2E-1: Say hello\nStatus: In Progress") { summary in
            await box.set(summary)
            return "Done — the task is now In Review."
        }
        let prompt = """
        Call the get_task tool, then call the submit_for_review tool with the summary "hello from e2e". Do nothing else.
        """
        let arguments = [
            "-p", prompt, "--model", "haiku",
            "--mcp-config", session.configPath, "--allowedTools", TaskAgentTools.allowedTools,
            "--strict-mcp-config", "--output-format", "text",
        ]
        let output = try await Self.run("/usr/bin/env", ["claude"] + arguments, in: directory)
        print("claude output:", output)
        let summary = await box.value
        XCTAssertEqual(summary, "hello from e2e")
        await server.unregister(session)
    }

    /// Süreç ayrı bir kuyrukta beklenir — cooperative pool'u bloklamaz (karar 86).
    private static func run(_ executable: String, _ arguments: [String], in directory: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private actor Box {
    var value: String?
    func set(_ value: String) { self.value = value }
}
