import Foundation
import XCTest
@testable import LumiTerminal

/// Karar 141: koşan claude'un argv'sinden resume bayrakları.
final class ClaudeLaunchArgumentsTests: XCTestCase {
    func testKeepsWhitelistedFlagsAndDropsSessionAndOneShotArguments() {
        let argv = [
            "/Users/dev/.local/bin/claude", "--model", "opus", "--resume", "abc", "-c",
            "--add-dir", "../a", "../b", "--dangerously-skip-permissions", "fix it",
            "--worktree", "feat", "-p", "--permission-mode=plan", "--name", "x", "--session-id", "u",
        ]
        XCTAssertEqual(ClaudeLaunchArguments.resumable(fromProcessArguments: argv), [
            "--model", "opus", "--add-dir", "../a", "../b", "--dangerously-skip-permissions",
            "--permission-mode=plan",
        ])
    }

    func testNonClaudeForegroundProcessYieldsNil() {
        XCTAssertNil(ClaudeLaunchArguments.resumable(fromProcessArguments: ["vim", "--model", "x"]))
        XCTAssertNil(ClaudeLaunchArguments.resumable(fromProcessArguments: []))
    }

    func testNodeInstallIsRecognized() {
        let argv = ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--effort", "high"]
        XCTAssertEqual(ClaudeLaunchArguments.resumable(fromProcessArguments: argv), ["--effort", "high"])
    }

    func testDoubleDashEndsOptionsAndMissingValueIsDropped() {
        XCTAssertEqual(ClaudeLaunchArguments.filter(["--verbose", "--", "--model", "x"]), ["--verbose"])
        XCTAssertEqual(ClaudeLaunchArguments.filter(["--model"]), [])
        XCTAssertEqual(ClaudeLaunchArguments.filter(["--add-dir", "--ide"]), ["--ide"])
    }

    func testResumeCommandCarriesQuotedFlags() {
        XCTAssertEqual(
            ClaudeSessionCommand.resumeCommand(
                sessionID: "s1", arguments: ["--model", "opus", "--append-system-prompt", "be brief", "--worktree", "w"]
            ),
            "claude --model opus --append-system-prompt 'be brief' --resume s1 || claude --model opus --append-system-prompt 'be brief'"
        )
        XCTAssertEqual(ClaudeSessionCommand.resumeCommand(sessionID: "s1"), "claude --resume s1 || claude")
    }

    func testResumeCommandRoundTripsThroughPrepare() {
        let id = "11111111-2222-3333-4444-555555555555"
        let command = ClaudeSessionCommand.resumeCommand(sessionID: id, arguments: ["--model", "opus"])
        let prepared = ClaudeSessionCommand.prepare(command: command)
        XCTAssertEqual(prepared.command, command)
        XCTAssertEqual(prepared.sessionID, id)
    }

    func testProcessArgumentsParseAndLiveRead() {
        var buffer: [UInt8] = []
        withUnsafeBytes(of: Int32(2)) { buffer += $0 }
        buffer += Array("/bin/claude".utf8) + [0, 0, 0]
        buffer += Array("claude".utf8) + [0] + Array("a b\nc".utf8) + [0] + Array("ENV=1".utf8) + [0]
        XCTAssertEqual(ProcessArguments.parse(buffer), ["claude", "a b\nc"])

        let own = ProcessArguments.read(pid: getpid())
        XCTAssertEqual(own?.count, CommandLine.arguments.count)
    }
}
