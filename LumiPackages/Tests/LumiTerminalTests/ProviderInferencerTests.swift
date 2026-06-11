import XCTest
@testable import LumiTerminal

final class ProviderInferencerTests: XCTestCase {
    func testInputCodexCommand() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("codex\r")
        XCTAssertEqual(inferencer.hint, .codex)
    }

    func testInputClaudeWithArguments() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("claude --model opus\r")
        XCTAssertEqual(inferencer.hint, .claude)
    }

    func testInputSubstringDoesNotMatch() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("claudette\r")
        XCTAssertEqual(inferencer.hint, .unknown)
        inferencer.observeInput("xcodex\r")
        XCTAssertEqual(inferencer.hint, .unknown)
    }

    func testInputIsTrimmedBeforeMatch() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("  codex  ")
        XCTAssertEqual(inferencer.hint, .codex)
    }

    func testOutputOpenAICodexAlwaysWins() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("claude\r")
        XCTAssertEqual(inferencer.hint, .claude)
        inferencer.observeOutput("Welcome to OpenAI Codex CLI")
        XCTAssertEqual(inferencer.hint, .codex)
    }

    func testOutputClaudeCodeOnlyFromUnknown() {
        var fresh = ProviderInferencer()
        fresh.observeOutput("Claude Code v2.0")
        XCTAssertEqual(fresh.hint, .claude)

        // Asimetri: codex hint'i output'taki "claude code" ile DÜŞMEZ (spec/10 §6)
        var codexFirst = ProviderInferencer()
        codexFirst.observeInput("codex\r")
        codexFirst.observeOutput("mentions claude code somewhere")
        XCTAssertEqual(codexFirst.hint, .codex)
    }

    func testOSCHintOverridesBothWays() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("codex\r")
        inferencer.applyOSCHint(.claude)
        XCTAssertEqual(inferencer.hint, .claude)
        inferencer.applyOSCHint(.codex)
        XCTAssertEqual(inferencer.hint, .codex)
    }

    func testOSCUnknownHintIgnored() {
        var inferencer = ProviderInferencer()
        inferencer.observeInput("claude\r")
        inferencer.applyOSCHint(.unknown)
        XCTAssertEqual(inferencer.hint, .claude)
    }
}
