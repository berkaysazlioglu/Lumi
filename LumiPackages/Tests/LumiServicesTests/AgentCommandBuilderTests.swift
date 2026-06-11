import Foundation
import XCTest
import LumiKit
@testable import LumiServices

final class AgentCommandBuilderTests: XCTestCase {
    private var tempDir: URL!
    private var builder: AgentCommandBuilder!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-builder-\(UUID().uuidString)")
        builder = AgentCommandBuilder(tempDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testNonAgentCommandPassesThrough() throws {
        // `claude`/`codex` ile başlamayan içerik DOKUNULMAZ (spec/13 §3.7)
        let result = try builder.build(
            content: "git pull\r",
            provider: .claude,
            claude: ClaudeAgentConfig(model: "sonnet"),
            codex: nil
        )
        XCTAssertEqual(result, "git pull\r")
    }

    func testClaudeFlagInjectionWithSeparator() throws {
        let config = ClaudeAgentConfig(
            model: "sonnet",
            allowedTools: ["Read", "Bash(git *)"],
            permissionMode: "plan",
            maxTurns: 10
        )
        let result = try builder.build(
            content: "claude \"do the thing\"\r",
            provider: .claude,
            claude: config,
            codex: nil
        )
        XCTAssertEqual(
            result,
            "claude --model sonnet --allowedTools \"Read\" \"Bash(git *)\" "
                + "--permission-mode plan --max-turns 10 -- \"do the thing\"\r"
        )
    }

    func testClaudeSystemPromptsWrittenToTempFiles() throws {
        let config = ClaudeAgentConfig(
            systemPrompt: "full replacement",
            appendSystemPrompt: "extra context"
        )
        let result = try builder.build(
            content: "claude \".\"\r",
            provider: .claude,
            claude: config,
            codex: nil
        )
        XCTAssertTrue(result.contains("--system-prompt-file '"))
        XCTAssertTrue(result.contains("--append-system-prompt-file '"))
        XCTAssertTrue(result.hasSuffix(" -- \".\"\r"))

        // Temp dosyalar gerçekten yazılmış ve içerik doğru olmalı
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(files.count, 2)
        let systemFile = try XCTUnwrap(files.first { $0.hasPrefix("system-prompt-") })
        let written = try String(
            contentsOf: tempDir.appendingPathComponent(systemFile), encoding: .utf8
        )
        XCTAssertEqual(written, "full replacement")
    }

    func testClaudeWithoutConfigUnchanged() throws {
        let result = try builder.build(
            content: "claude \"hi\"\r", provider: .claude, claude: nil, codex: nil
        )
        XCTAssertEqual(result, "claude \"hi\"\r")
    }

    func testRemapClaudeToCodexProvider() throws {
        // Satır başındaki `claude` provider binary'sine çevrilir + model enjekte
        let result = try builder.build(
            content: "claude \"prompt\"\r",
            provider: .codex,
            claude: nil,
            codex: CodexAgentConfig(model: "o5")
        )
        XCTAssertEqual(result, "codex --model o5 \"prompt\"\r")
    }

    func testCodexSkipsInjectionWhenModelPresent() throws {
        let content = "codex --model existing \"x\"\r"
        let result = try builder.build(
            content: content, provider: .codex, claude: nil, codex: CodexAgentConfig(model: "o5")
        )
        XCTAssertEqual(result, content)
    }

    func testCodexWithoutModelConfigUnchanged() throws {
        let result = try builder.build(
            content: "codex\r", provider: .codex, claude: nil, codex: nil
        )
        XCTAssertEqual(result, "codex\r")
    }
}
