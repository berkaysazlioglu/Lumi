import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiServices

/// Karar 123: orchestrator Codex'inin açılış script'i ve `codex queue`.
final class CodexOrchestratorLauncherTests: XCTestCase {
    private var directory: URL!
    private var runner: FakeProcessRunner!
    private var locator: FakeBinaryLocator!
    private var launcher: CodexOrchestratorLauncher!

    private let control = OrchestratorControlEndpoint(port: 4242, token: "secret-token")

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("orch-\(UUID().uuidString)")
        runner = FakeProcessRunner()
        locator = FakeBinaryLocator(paths: ["codex": "/bin/codex"])
        launcher = CodexOrchestratorLauncher(workingDirectory: directory, runner: runner, locator: locator)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func request(resume: String? = nil, instructions: String = "Be the orchestrator.") -> OrchestratorLaunchRequest {
        OrchestratorLaunchRequest(instructions: instructions, resumeThreadID: resume, control: control, codexHome: "/h")
    }

    // MARK: - Argümanlar

    func testArgumentsRunAutoModeWithOnlyLumiTools() {
        let args = CodexOrchestratorLauncher.arguments(for: request(), disabledServers: ["figma"])

        XCTAssertTrue(args.contains("--approve-for-me"), "auto mod: MCP çağrıları sorulmaz")
        XCTAssertFalse(args.contains("--dangerously-bypass-approvals-and-sandbox"))
        for feature in ["shell_tool", "unified_exec", "view_image", "multi_agent", "plugins", "apps"] {
            XCTAssertTrue(args.contains(feature), "kapalı değil: \(feature)")
        }
        XCTAssertTrue(args.contains(#"web_search="disabled""#))
        XCTAssertTrue(args.contains("check_for_update_on_startup=false"), "güncelleme sorusu açılışı bekletmez")
        XCTAssertTrue(args.contains(#"mcp_servers."figma".enabled=false"#), "kullanıcının MCP'leri kapanır")
        XCTAssertTrue(args.contains(#"mcp_servers.lumi.url="http://127.0.0.1:4242/mcp""#))
        XCTAssertTrue(args.contains(#"mcp_servers.lumi.bearer_token_env_var="LUMI_MCP_TOKEN""#))
        XCTAssertFalse(args.joined().contains("secret-token"), "token argv'de olmaz")
        XCTAssertEqual(args.last, #"developer_instructions="Be the orchestrator.""#)
        XCTAssertNotEqual(args.first, "resume")
    }

    func testResumeComesFirst() {
        let args = CodexOrchestratorLauncher.arguments(for: request(resume: "t-1"), disabledServers: [])
        XCTAssertEqual(Array(args.prefix(2)), ["resume", "t-1"])
    }

    func testTOMLStringEscapesQuotesBackslashesAndNewlines() {
        XCTAssertEqual(
            CodexOrchestratorLauncher.tomlString("a \"b\" \\ c\nd\te\u{01}"),
            #""a \"b\" \\ c\nd\te\u0001""#
        )
        XCTAssertEqual(CodexOrchestratorLauncher.tomlString("çğü — ok"), #""çğü — ok""#)
    }

    // MARK: - prepare

    func testPrepareWritesPrivateScriptAndPassesTokenThroughEnvironment() async throws {
        await runner.stub(
            commandLine: "/usr/bin/env CODEX_HOME=/h /bin/codex mcp list --json",
            with: .success(#"[{"name":"lumi"},{"name":"unity editor"}]"#)
        )

        let plan = try await launcher.prepare(request(instructions: "it's \"multi\"\nline"))

        let script = directory.appendingPathComponent("launch.sh")
        XCTAssertEqual(plan.command, "exec /bin/sh " + shellQuoted(script.path))
        XCTAssertEqual(plan.environment, ["CODEX_HOME": "/h", "LUMI_MCP_TOKEN": "secret-token"])
        let attributes = try FileManager.default.attributesOfItem(atPath: script.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(text.contains("exec '/bin/codex'"))
        XCTAssertTrue(text.contains(#"'mcp_servers."unity editor".enabled=false'"#))
        XCTAssertFalse(text.contains(#"mcp_servers."lumi".enabled=false"#), "Lumi'nin kendi sunucusu kapanmaz")
        XCTAssertTrue(text.contains(#"developer_instructions="it'\''s \"multi\"\nline""#))
        XCTAssertFalse(text.contains("secret-token"))
    }

    func testUnreadableMCPListDoesNotBlockLaunch() async throws {
        await runner.stub(executable: "/usr/bin/env", with: .failure(stderr: "boom"))
        let plan = try await launcher.prepare(request())
        XCTAssertFalse(plan.command.isEmpty)
    }

    func testMissingCodexIsReportedAsCLINotFound() async {
        await locator.setPath(nil, for: "codex")
        do {
            _ = try await launcher.prepare(request())
            XCTFail("hata beklendi")
        } catch {
            XCTAssertEqual(error as? LumiError, .cliNotFound(binary: "codex"))
        }
    }

    // MARK: - queue

    func testQueueRunsCodexQueueForTheThreadUnderTheAccountHome() async throws {
        try await launcher.queue("<lumi-activity>x</lumi-activity>", thread: "t-1", codexHome: "/h")

        let commandLines = await runner.commandLines
        XCTAssertEqual(commandLines, [
            "/usr/bin/env CODEX_HOME=/h /bin/codex queue --thread t-1 --message <lumi-activity>x</lumi-activity>",
        ])
    }

    func testQueueFailureCarriesStderr() async {
        await runner.stub(executable: "/usr/bin/env", with: .failure(stderr: "unknown thread"))
        do {
            try await launcher.queue("x", thread: "t-1", codexHome: nil)
            XCTFail("hata beklendi")
        } catch {
            XCTAssertEqual(error as? LumiError, .orchestratorQueueFailed(detail: "unknown thread"))
        }
    }
}
