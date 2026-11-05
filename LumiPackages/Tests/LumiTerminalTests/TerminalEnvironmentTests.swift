import LumiKit
import XCTest
@testable import LumiTerminal

final class TerminalEnvironmentTests: XCTestCase {
    func testSetsTermToXterm256Color() {
        // Arrange
        let base = ["TERM": "dumb"]

        // Act
        let env = TerminalEnvironment.childEnvironment(base: base)

        // Assert
        XCTAssertEqual(env["TERM"], "xterm-256color")
    }

    func testDeclaresTruecolorSupportRegardlessOfHostTerminal() {
        // Arrange — Finder launch'ında COLORTERM hiç yoktur
        let base: [String: String] = [:]

        // Act
        let env = TerminalEnvironment.childEnvironment(base: base)

        // Assert
        XCTAssertEqual(env["COLORTERM"], "truecolor")
    }

    func testOverridesInheritedColortermFromOuterTerminal() {
        // Arrange — dev'de dış terminalin (iTerm vb.) değeri miras kalır;
        // PTY child'ın gördüğü emülatör Lumi'dir, değer Lumi'nin yeteneğini taşımalı
        let base = ["COLORTERM": "somethingelse"]

        // Act
        let env = TerminalEnvironment.childEnvironment(base: base)

        // Assert
        XCTAssertEqual(env["COLORTERM"], "truecolor")
    }

    func testDefaultsLangOnlyWhenMissing() {
        // Arrange
        let missing: [String: String] = [:]
        let present = ["LANG": "tr_TR.UTF-8"]

        // Act
        let envMissing = TerminalEnvironment.childEnvironment(base: missing)
        let envPresent = TerminalEnvironment.childEnvironment(base: present)

        // Assert
        XCTAssertEqual(envMissing["LANG"], "en_US.UTF-8")
        XCTAssertEqual(envPresent["LANG"], "tr_TR.UTF-8")
    }

    // MARK: - Karar 45: hook uç noktası

    func testInjectsHookTripleWhenEndpointGiven() {
        let id = TerminalID()
        let env = TerminalEnvironment.childEnvironment(
            base: [:],
            hookEndpoint: AgentHookEndpoint(port: 5150, token: "tok"),
            terminalID: id
        )
        XCTAssertEqual(env["LUMI_TERMINAL_ID"], id.description)
        XCTAssertEqual(env["LUMI_AGENT_HOOK_PORT"], "5150")
        XCTAssertEqual(env["LUMI_AGENT_HOOK_TOKEN"], "tok")
    }

    func testStripsInheritedHookTripleWhenHooksDisabled() {
        // `swift run` altında dış Lumi'nin env'i miras kalabilir; başka bir
        // örneğin portuna post edilmesin.
        let base = ["LUMI_TERMINAL_ID": "stale", "LUMI_AGENT_HOOK_PORT": "1", "LUMI_AGENT_HOOK_TOKEN": "x"]
        let env = TerminalEnvironment.childEnvironment(base: base)
        XCTAssertNil(env["LUMI_TERMINAL_ID"])
        XCTAssertNil(env["LUMI_AGENT_HOOK_PORT"])
        XCTAssertNil(env["LUMI_AGENT_HOOK_TOKEN"])
    }

    func testPreservesUnrelatedVariables() {
        // Arrange
        let base = ["PATH": "/usr/bin", "HOME": "/Users/test"]

        // Act
        let env = TerminalEnvironment.childEnvironment(base: base)

        // Assert
        XCTAssertEqual(env["PATH"], "/usr/bin")
        XCTAssertEqual(env["HOME"], "/Users/test")
    }

    func testDisablesOhMyZshUpdatePrompt() {
        // omz [Y/n] güncelleme sorusu launch komutunun ilk karakterini yiyordu
        // ("claude"→"laude"); Lumi shell'lerinde soru tamamen kapalı olmalı.
        let env = TerminalEnvironment.childEnvironment(base: [:])
        XCTAssertEqual(env["DISABLE_UPDATE_PROMPT"], "true")
        XCTAssertEqual(env["DISABLE_AUTO_UPDATE"], "true")
    }

    func testStripsInheritedClaudeSessionIdentity() {
        // Lumi bir claude oturumu içinden başlatılırsa child claude alt-oturum
        // sanıp transcript'i --session-id yoluna yazmıyordu; kimlik geçmemeli.
        let base = ["CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "abc",
                    "CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_EFFORT": "high",
                    "CLAUDE_CONFIG_DIR": "/keep/me"]
        let env = TerminalEnvironment.childEnvironment(base: base)
        XCTAssertNil(env["CLAUDECODE"])
        XCTAssertNil(env["CLAUDE_CODE_SESSION_ID"])
        XCTAssertNil(env["CLAUDE_CODE_CHILD_SESSION"])
        XCTAssertNil(env["CLAUDE_EFFORT"])
        XCTAssertEqual(env["CLAUDE_CONFIG_DIR"], "/keep/me")   // meşru ayar korunur
    }

    func testDeclaresTerminalImageSupportToClaudeCode() {
        // SwiftTerm XTVERSION'da kitty/ghostty demediği için Claude Code
        // görselleri kendiliğinden açmaz; miras temizliğinden sonra yazılmalı.
        let env = TerminalEnvironment.childEnvironment(base: ["CLAUDE_CODE_FORCE_TERMINAL_IMAGES": "0"])
        XCTAssertEqual(env["CLAUDE_CODE_FORCE_TERMINAL_IMAGES"], "1")
    }

    func testWritesClaudePluginDirectoriesAfterStrippingInheritedValue() {
        // Karar 142: açık modlar `--plugin-dir` vermeden her claude'a; dış
        // ortamdan miras kalan değer Lumi'ninkini ezmez.
        let env = TerminalEnvironment.childEnvironment(
            base: ["CLAUDE_CODE_PLUGIN_DIRS": "/outer"],
            claudePluginDirectories: ["/m/a", "/m/b"]
        )
        XCTAssertEqual(env["CLAUDE_CODE_PLUGIN_DIRS"], "/m/a:/m/b")
    }

    func testOmitsClaudePluginDirectoriesWhenNoModIsEnabled() {
        let env = TerminalEnvironment.childEnvironment(base: ["CLAUDE_CODE_PLUGIN_DIRS": "/outer"])
        XCTAssertNil(env["CLAUDE_CODE_PLUGIN_DIRS"])
    }

    func testLaunchOverridesReplaceInheritedCodexHome() {
        let env = TerminalEnvironment.childEnvironment(
            base: ["CODEX_HOME": "/system"], overrides: ["CODEX_HOME": "/managed"]
        )
        XCTAssertEqual(env["CODEX_HOME"], "/managed")
    }

    /// Karar 143: config dizini geçersiz kılması ve remote MCP değerleri miras geçmez;
    /// remote değerleri yalnız Lumi'nin Claude ortamı (`overrides`) yazar.
    func testLumiInstanceValuesDoNotLeakIntoChildren() {
        let base = ["LUMI_CONFIG_DIR": "/x", "LUMI_REMOTE_MCP_URL": "http://old", "LUMI_REMOTE_MCP_TOKEN": "old", "PATH": "/bin"]
        let plain = TerminalEnvironment.childEnvironment(base: base)
        XCTAssertNil(plain["LUMI_CONFIG_DIR"])
        XCTAssertNil(plain["LUMI_REMOTE_MCP_URL"])
        XCTAssertNil(plain["LUMI_REMOTE_MCP_TOKEN"])
        XCTAssertEqual(plain["PATH"], "/bin")
        let claude = TerminalEnvironment.childEnvironment(base: base, overrides: ["LUMI_REMOTE_MCP_URL": "http://new"])
        XCTAssertEqual(claude["LUMI_REMOTE_MCP_URL"], "http://new")
    }
}
