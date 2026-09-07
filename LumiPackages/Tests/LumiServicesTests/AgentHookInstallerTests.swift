import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 45: kurucu gerçek dosya sisteminde (geçici ev dizini) — script'ler,
/// Claude settings.json, Codex hooks.json + config.toml.
final class AgentHookInstallerTests: XCTestCase {
    private var home: URL!
    private var installer: AgentHookInstaller!

    override func setUp() async throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-hooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        installer = AgentHookInstaller(
            homeDirectory: home,
            scriptDirectory: home.appendingPathComponent(".lumi/hooks", isDirectory: true)
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeProviderDirs(claude: Bool = true, codex: Bool = true) throws {
        if claude { try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true) }
        if codex { try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true) }
    }

    private func json(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: home.appendingPathComponent(relative))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func outcome(_ results: [AgentHookInstallResult], _ provider: AgentProvider) -> AgentHookInstallResult.Outcome? {
        results.first { $0.provider == provider }?.outcome
    }

    func testSkipsProvidersWhoseHomeIsMissing() async {
        let results = await installer.install()
        XCTAssertEqual(outcome(results, .claude), .skipped(reason: "Claude Code not installed"))
        XCTAssertEqual(outcome(results, .codex), .skipped(reason: "Codex not installed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path), "başkasının dizini yaratılmaz")
    }

    func testInstallWritesScriptsAndSettingsThenBecomesNoOp() async throws {
        try makeProviderDirs()
        try "{\n  \"model\": \"opus\"\n}\n".write(to: home.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)
        try "model = \"gpt-5\"\n".write(to: home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)

        let first = await installer.install()
        XCTAssertEqual(outcome(first, .claude), .installed)
        XCTAssertEqual(outcome(first, .codex), .installed)

        // Script'ler çalıştırılabilir
        for provider in AgentProvider.allCases {
            let path = installer.scriptPath(for: provider)
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            XCTAssertEqual(attrs[.posixPermissions] as? Int, 0o755, path)
            XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), AgentHookScript.posix(provider: provider))
        }

        // Claude: yabancı anahtar korunur, tüm event'ler kayıtlı
        let settings = try json(".claude/settings.json")
        XCTAssertEqual(settings["model"] as? String, "opus")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(ClaudeHookSettings.events.map(\.name)))

        // Codex: hooks.json + güven kayıtları
        let codexHooks = try json(".codex/hooks.json")
        XCTAssertEqual(Set((codexHooks["hooks"] as? [String: Any])?.keys ?? [:].keys), Set(CodexHookSettings.events))
        let toml = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        XCTAssertTrue(toml.hasPrefix("model = \"gpt-5\"\n"))
        XCTAssertTrue(toml.contains("[hooks.state]"))
        let hooksPath = home.appendingPathComponent(".codex").resolvingSymlinksInPath().appendingPathComponent("hooks.json").path
        XCTAssertTrue(toml.contains("[hooks.state.\"\(hooksPath):stop:0:0\"]"))
        let expectedHash = CodexHookTrust.trustedHash(
            label: "stop",
            command: AgentHookScript.managedCommand(scriptPath: installer.scriptPath(for: .codex), provider: .codex),
            timeoutSeconds: CodexHookSettings.timeoutSeconds
        )
        XCTAssertTrue(toml.contains("trusted_hash = \"\(expectedHash)\""))

        let second = await installer.install()
        XCTAssertEqual(outcome(second, .claude), .unchanged)
        XCTAssertEqual(outcome(second, .codex), .unchanged)
    }

    func testCorruptSettingsFileIsNeverOverwritten() async throws {
        try makeProviderDirs(codex: false)
        let file = home.appendingPathComponent(".claude/settings.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)

        let results = await installer.install()

        guard case .failed = outcome(results, .claude) else { return XCTFail("failed beklenirdi: \(results)") }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ not json")
    }

    func testUninstallRemovesManagedEntriesScriptsAndTrust() async throws {
        try makeProviderDirs()
        try "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo mine\"}]}]}}"
            .write(to: home.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)
        _ = await installer.install()

        let results = await installer.uninstall()

        XCTAssertEqual(outcome(results, .claude), .removed)
        XCTAssertEqual(outcome(results, .codex), .removed)
        let hooks = try XCTUnwrap(try json(".claude/settings.json")["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["Stop"], "kullanıcının kendi hook'u kalır")
        XCTAssertTrue(((try json(".codex/hooks.json")["hooks"] as? [String: Any]) ?? [:]).isEmpty)
        let toml = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        XCTAssertFalse(toml.contains("trusted_hash"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptDirectory.path))
    }

    func testStaleScriptPathFromOldHomeIsSwept() async throws {
        try makeProviderDirs(codex: false)
        let stale = AgentHookScript.managedCommand(scriptPath: "/nonexistent/.lumi/hooks/lumi-claude-hook.sh", provider: .claude)
        try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [["hooks": [["type": "command", "command": stale]]]]]])
            .write(to: home.appendingPathComponent(".claude/settings.json"))

        _ = await installer.install()

        let stop = try XCTUnwrap((try json(".claude/settings.json")["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, [AgentHookScript.managedCommand(scriptPath: installer.scriptPath(for: .claude), provider: .claude)])
    }
}
