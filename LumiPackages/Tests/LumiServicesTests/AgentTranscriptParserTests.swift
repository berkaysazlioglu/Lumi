import XCTest
@testable import LumiServices
import LumiKit

/// Gerçek `~/.claude/projects` ve `~/.codex/sessions` satırlarından türetilmiş
/// fixture'larla transkript ayrıştırma.
final class AgentTranscriptParserTests: XCTestCase {
    // MARK: - Claude

    func testClaudeTranscriptExtractsBranchModelCountAndTurns() throws {
        let lines = [
            #"{"type":"mode","mode":"normal","sessionId":"s-1"}"#,
            claudeUser(text: "<local-command-caveat>Caveat: local commands</local-command-caveat>"),
            claudeUser(text: "<command-name>/model</command-name>"),
            claudeUser(text: "Explorer sekmesini okunur yap"),
            claudeAssistantBlocks(#"{"type":"thinking","thinking":"…"},{"type":"text","text":"Dosyalara bakıyorum"}"#),
            claudeAssistantBlocks(#"{"type":"tool_use","id":"t1","name":"Read","input":{}}"#),
            claudeUserToolResult(),
            claudeAssistantBlocks(#"{"type":"text","text":"Kart eklendi"}"#),
        ]

        let transcript = parse(lines, provider: .claude)

        XCTAssertEqual(transcript.cwd, "/repo")
        XCTAssertEqual(transcript.sessionID, "s-1")
        XCTAssertEqual(transcript.gitBranch, "main")
        XCTAssertEqual(transcript.model, "claude-opus-4-1")
        XCTAssertEqual(transcript.firstPrompt, "Explorer sekmesini okunur yap")
        XCTAssertEqual(transcript.messageCount, 3, "tool_use/tool_result ve meta satırları sayılmaz")
        XCTAssertEqual(transcript.turns.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(transcript.turns.last?.text, "Kart eklendi")
        XCTAssertNotNil(transcript.turns.first?.timestamp)
    }

    func testClaudeMetaFlagAndSystemReminderAreSkipped() throws {
        let lines = [
            #"{"type":"user","isMeta":true,"cwd":"/repo","sessionId":"s-2","message":{"role":"user","content":"Bootstrap note"}}"#,
            claudeUser(text: "<system-reminder>hidden</system-reminder>"),
            claudeUser(text: "Gerçek istem"),
        ]

        let transcript = parse(lines, provider: .claude)

        XCTAssertEqual(transcript.firstPrompt, "Gerçek istem")
        XCTAssertEqual(transcript.messageCount, 1)
    }

    // MARK: - Codex

    func testCodexTranscriptUsesSessionMetaAndTurnContext() throws {
        let lines = [
            #"{"timestamp":"2026-08-06T11:28:31.930Z","type":"session_meta","payload":{"id":"c-1","cwd":"/repo","git":{"branch":"feature/history","commit_hash":"abc"}}}"#,
            #"{"type":"turn_context","payload":{"cwd":"/repo","model":"gpt-5.6-sol"}}"#,
            codexMessage(role: "developer", type: "input_text", text: "You are Codex"),
            codexMessage(role: "user", type: "input_text", text: "<recommended_plugins>Airtable</recommended_plugins>"),
            codexMessage(role: "user", type: "input_text", text: "Testleri düzelt"),
            #"{"type":"event_msg","payload":{"type":"user_message","message":"Testleri düzelt"}}"#,
            codexMessage(role: "assistant", type: "output_text", text: "Testleri koşuyorum"),
        ]

        let transcript = parse(lines, provider: .codex)

        XCTAssertEqual(transcript.cwd, "/repo")
        XCTAssertEqual(transcript.sessionID, "c-1")
        XCTAssertEqual(transcript.gitBranch, "feature/history")
        XCTAssertEqual(transcript.model, "gpt-5.6-sol")
        XCTAssertEqual(transcript.firstPrompt, "Testleri düzelt", "developer rolü ve plugin listesi istem değildir")
        XCTAssertEqual(
            transcript.messageCount, 2,
            "event_msg kopyası response_item ile aynı metni tekrarlar, tekilleştirilir"
        )
        XCTAssertEqual(transcript.turns.map(\.role), [.user, .assistant])
    }

    // MARK: - Kırpma

    func testTurnTruncationAppendsEllipsis() throws {
        let long = String(repeating: "a", count: 500)
        let turn = AgentHistoryTurn(role: .user, text: long).truncated(to: 400)

        XCTAssertEqual(turn.text.count, 401)
        XCTAssertTrue(turn.text.hasSuffix("…"))
        XCTAssertEqual(AgentHistoryTurn(role: .user, text: "kısa").truncated(to: 400).text, "kısa")
    }

    func testModelLabelDropsVendorPrefixAndDateSuffix() {
        XCTAssertEqual(entry(model: "claude-opus-4-1").modelLabel, "opus-4-1")
        XCTAssertEqual(entry(model: "claude-sonnet-4-20250514").modelLabel, "sonnet-4")
        XCTAssertEqual(entry(model: "gpt-5.6-sol").modelLabel, "gpt-5.6-sol")
        XCTAssertNil(entry(model: nil).modelLabel)
    }

    // MARK: - Yardımcılar

    private func parse(_ lines: [String], provider: AgentProvider) -> AgentTranscriptParser.Transcript {
        let records = lines.compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        XCTAssertEqual(records.count, lines.count, "fixture JSON'u geçersiz")
        return AgentTranscriptParser(provider: provider).parse(records)
    }

    private func entry(model: String?) -> AgentHistoryEntry {
        AgentHistoryEntry(provider: .claude, sessionID: "s", title: "t", updatedAt: .now, logPath: "/tmp/s", model: model)
    }

    /// `text` JSON'a gömülürken kaçışlanır (`<...>` sarmalayıcıları düz metindir).
    private func claudeUser(text: String) -> String {
        let content = String(
            data: try! JSONSerialization.data(withJSONObject: [text]), encoding: .utf8
        )!.dropFirst().dropLast()
        return """
        {"type":"user","cwd":"/repo","gitBranch":"main","sessionId":"s-1",\
        "timestamp":"2026-09-04T08:00:07.742Z",\
        "message":{"role":"user","content":\(content)}}
        """
    }

    private func claudeUserToolResult() -> String {
        #"{"type":"user","cwd":"/repo","sessionId":"s-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#
    }

    private func claudeAssistantBlocks(_ blocks: String) -> String {
        #"{"type":"assistant","cwd":"/repo","sessionId":"s-1","timestamp":"2026-09-04T08:00:09.100Z","message":{"role":"assistant","model":"claude-opus-4-1","content":[\#(blocks)]}}"#
    }

    private func codexMessage(role: String, type: String, text: String) -> String {
        #"{"type":"response_item","payload":{"type":"message","role":"\#(role)","content":[{"type":"\#(type)","text":"\#(text)"}]}}"#
    }
}
