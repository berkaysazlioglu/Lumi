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
}
