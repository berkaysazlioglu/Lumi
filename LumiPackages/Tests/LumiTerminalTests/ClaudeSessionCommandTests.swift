import XCTest
@testable import LumiTerminal

final class ClaudeSessionCommandTests: XCTestCase {
    private let fixedID = "11111111-2222-3333-4444-555555555555"

    private func prepare(_ command: String?) -> (command: String?, sessionID: String?) {
        ClaudeSessionCommand.prepare(command: command, generateID: { self.fixedID })
    }

    // MARK: - Enjeksiyon

    func testInjectsSessionIDIntoPlainClaudeCommand() {
        // Arrange & Act
        let result = prepare("claude")

        // Assert
        XCTAssertEqual(result.command, "claude --session-id \(fixedID)")
        XCTAssertEqual(result.sessionID, fixedID)
    }

    func testInjectsSessionIDPreservingExistingArguments() {
        let result = prepare("claude --dangerously-skip-permissions")

        XCTAssertEqual(
            result.command,
            "claude --dangerously-skip-permissions --session-id \(fixedID)"
        )
        XCTAssertEqual(result.sessionID, fixedID)
    }

    // MARK: - Dokunulmayan komutlar

    func testNilCommandPassesThrough() {
        let result = prepare(nil)

        XCTAssertNil(result.command)
        XCTAssertNil(result.sessionID)
    }

    func testNonClaudeCommandPassesThrough() {
        let result = prepare("codex")

        XCTAssertEqual(result.command, "codex")
        XCTAssertNil(result.sessionID)
    }

    func testClaudePrefixedButDifferentBinaryPassesThrough() {
        // "claudex" gibi bir binary claude DEĞİLDİR — token sınırı aranır
        let result = prepare("claudex --foo")

        XCTAssertEqual(result.command, "claudex --foo")
        XCTAssertNil(result.sessionID)
    }

    // MARK: - Mevcut oturum flag'leri: komut değişmez, ID çıkarılır

    func testExtractsIDFromExistingSessionIDFlag() {
        let command = "claude --session-id aaaabbbb-cccc-dddd-eeee-ffff00001111"

        let result = prepare(command)

        XCTAssertEqual(result.command, command)
        XCTAssertEqual(result.sessionID, "aaaabbbb-cccc-dddd-eeee-ffff00001111")
    }

    func testExtractsIDFromResumeFlag() {
        let command = "claude --resume aaaabbbb-cccc-dddd-eeee-ffff00001111 || claude"

        let result = prepare(command)

        XCTAssertEqual(result.command, command)
        XCTAssertEqual(result.sessionID, "aaaabbbb-cccc-dddd-eeee-ffff00001111")
    }

    func testExtractsIDFromShortResumeFlag() {
        let command = "claude -r aaaabbbb-cccc-dddd-eeee-ffff00001111"

        let result = prepare(command)

        XCTAssertEqual(result.command, command)
        XCTAssertEqual(result.sessionID, "aaaabbbb-cccc-dddd-eeee-ffff00001111")
    }

    func testContinueFlagLeavesCommandUntouchedWithoutID() {
        // -c/--continue oturumu CWD'den seçer; ID bilinemez → enjeksiyon da yapılmaz
        let result = prepare("claude -c")

        XCTAssertEqual(result.command, "claude -c")
        XCTAssertNil(result.sessionID)
    }

    // MARK: - Resume komutu üretimi + roundtrip

    func testResumeCommandFallsBackToFreshClaude() {
        let command = ClaudeSessionCommand.resumeCommand(sessionID: fixedID)

        XCTAssertEqual(command, "claude --resume \(fixedID) || claude")
    }

    func testResumeCommandRoundTripKeepsSameID() {
        // Restore spawn'ı da prepare()'dan geçer: ID aynı kalmalı, komut bozulmamalı
        let resume = ClaudeSessionCommand.resumeCommand(sessionID: fixedID)

        let result = prepare(resume)

        XCTAssertEqual(result.command, resume)
        XCTAssertEqual(result.sessionID, fixedID)
    }
}
