import Foundation
import XCTest
@testable import LumiKit

/// Karar 45: hook JSON'u → `AgentHookEvent` ve yardımcı türevler.
final class AgentHookEventTests: XCTestCase {
    private let terminal = TerminalID()

    private func parse(_ json: String, provider: AgentProvider = .claude) -> AgentHookEvent? {
        AgentHookEvent.parse(provider: provider, terminalID: terminal, body: Data(json.utf8))
    }

    func testParsesCoreFields() throws {
        let event = try XCTUnwrap(parse("""
        {"hook_event_name":"PreToolUse","session_id":"s1","agent_id":"a-1",
         "tool_name":"Bash","source":"startup","trigger":"manual","is_interrupt":true,
         "prompt":"  hello  "}
        """))

        XCTAssertEqual(event.kind, .preToolUse)
        XCTAssertEqual(event.agentID, "a-1")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.source, "startup")
        XCTAssertEqual(event.trigger, "manual")
        XCTAssertTrue(event.isInterrupt)
        XCTAssertEqual(event.promptHead, "hello")
        XCTAssertFalse(event.isLead)
        XCTAssertEqual(event.terminalID, terminal)
        XCTAssertEqual(event.provider, .claude)
    }

    func testMissingEventNameOrNonObjectBodyIsRejected() {
        XCTAssertNil(parse("{\"session_id\":\"x\"}"))
        XCTAssertNil(parse("[1,2]"))
        XCTAssertNil(parse("not json"))
    }

    func testUnknownEventNameIsPreservedNotDropped() throws {
        let event = try XCTUnwrap(parse("{\"hook_event_name\":\"Notification\"}"))
        XCTAssertEqual(event.kind, .unknown("Notification"))
        XCTAssertTrue(event.isLead)
    }

    func testCodexToolNameFallsBackToNameField() throws {
        let event = try XCTUnwrap(parse("{\"hook_event_name\":\"PreToolUse\",\"name\":\"request_user_input\"}", provider: .codex))
        XCTAssertEqual(event.toolName, "request_user_input")
        XCTAssertTrue(event.isUserQuestionTool)
    }

    func testUserQuestionToolDetectionIsCaseAndPunctuationInsensitive() {
        func event(_ tool: String?) -> AgentHookEvent {
            AgentHookEvent(provider: .claude, terminalID: terminal, kind: .preToolUse, toolName: tool)
        }
        XCTAssertTrue(event("AskUserQuestion").isUserQuestionTool)
        XCTAssertTrue(event("ask_user_question").isUserQuestionTool)
        XCTAssertTrue(event("RequestUserInput").isUserQuestionTool)
        XCTAssertFalse(event("Bash").isUserQuestionTool)
        XCTAssertFalse(event(nil).isUserQuestionTool)
    }

    func testCompactContinuationPromptIsRecognisedByPrefix() {
        let compact = AgentHookEvent(
            provider: .claude, terminalID: terminal, kind: .userPromptSubmit,
            promptHead: "This session is being continued from a previous conversation that ran out of context."
        )
        let real = AgentHookEvent(provider: .claude, terminalID: terminal, kind: .userPromptSubmit, promptHead: "fix the bug")
        XCTAssertTrue(compact.isCompactContinuationPrompt)
        XCTAssertFalse(real.isCompactContinuationPrompt)
    }

    func testPromptHeadIsTruncated() throws {
        let long = String(repeating: "x", count: 500)
        let event = try XCTUnwrap(parse("{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"\(long)\"}"))
        XCTAssertEqual(event.promptHead?.count, AgentHookEvent.promptHeadLimit)
    }

    func testBackgroundTasksKeepOnlyRunningAgentTasks() throws {
        let event = try XCTUnwrap(parse("""
        {"hook_event_name":"Stop","background_tasks":[
          {"id":"a1","type":"subagent","status":"running"},
          {"id":"a2","type":"teammate","status":"idle"},
          {"id":"a3","type":"subagent","status":"completed"},
          {"id":"b1","type":"shell","status":"running"},
          {"type":"subagent","status":"running"}
        ]}
        """))
        XCTAssertEqual(event.runningBackgroundAgentIDs, ["a1", "a2"])
    }

    func testBackgroundTasksAbsentIsNilNotEmpty() throws {
        let event = try XCTUnwrap(parse("{\"hook_event_name\":\"Stop\"}"))
        XCTAssertNil(event.runningBackgroundAgentIDs)
    }

    // MARK: - Uç nokta env'i

    func testEndpointEnvironmentCarriesTerminalPortAndToken() {
        let endpoint = AgentHookEndpoint(port: 4242, token: "abc")
        let env = endpoint.environment(for: terminal)
        XCTAssertEqual(env["LUMI_TERMINAL_ID"], terminal.description)
        XCTAssertEqual(env["LUMI_AGENT_HOOK_PORT"], "4242")
        XCTAssertEqual(env["LUMI_AGENT_HOOK_TOKEN"], "abc")
    }

    // MARK: - Sağlayıcı çıkarımı

    func testProviderDetectionUsesFirstToken() {
        XCTAssertEqual(AgentProvider.detect(launchCommand: "claude --resume abc"), .claude)
        XCTAssertEqual(AgentProvider.detect(launchCommand: "  codex"), .codex)
        XCTAssertNil(AgentProvider.detect(launchCommand: "npm run claude"))
        XCTAssertNil(AgentProvider.detect(launchCommand: nil))
        XCTAssertNil(AgentProvider.detect(launchCommand: ""))
    }
}
