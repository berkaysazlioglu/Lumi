import Testing
import Foundation
@testable import LumiKit

@Suite struct TurnStatusReducerTests {
    private let term = TerminalID()
    private func event(_ kind: AgentHookEventKind, tool: String? = nil,
                       source: String? = nil, agentID: String? = nil) -> AgentHookEvent {
        AgentHookEvent(
            provider: .claude, terminalID: term, kind: kind, agentID: agentID,
            teammateName: nil, toolName: tool, source: source, trigger: nil,
            isInterrupt: false, promptHead: nil, runningBackgroundAgentIDs: nil
        )
    }

    @Test func promptStartsWorkingWithInjectedClock() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 100) })
        let s = r.reduce(event(.userPromptSubmit))
        #expect(s == ChatTurnStatus(working: true, startedAtMs: 100_000, tool: nil))
    }

    @Test func preToolSetsToolPostToolClearsIt() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        #expect(r.reduce(event(.preToolUse, tool: "Bash"))?.tool == "Bash")
        #expect(r.reduce(event(.postToolUse, tool: "Bash"))?.tool == nil)
        #expect(r.status.working == true)   // working korunur
    }

    @Test func stopResetsToIdle() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        #expect(r.reduce(event(.stop)) == .idle)
    }

    @Test func clearSessionStartResets() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        #expect(r.reduce(event(.sessionStart, source: "clear")) == .idle)
    }

    @Test func subagentAndUnrelatedEventsAreIgnored() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        #expect(r.reduce(event(.preToolUse, tool: "Bash", agentID: "sub-1")) == nil) // subagent → yok
        #expect(r.reduce(event(.permissionRequest)) == nil)
        #expect(r.reduce(event(.sessionStart, source: "resume")) == nil)             // clear değil
    }

    @Test func idempotentSameStatusNotReemitted() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        _ = r.reduce(event(.stop))
        #expect(r.reduce(event(.stop)) == nil)   // zaten idle → nil
    }

    @Test func interruptResetsWorkingToIdle() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        _ = r.reduce(event(.preToolUse, tool: "Bash"))
        #expect(r.interrupt() == .idle)
        #expect(r.status == .idle)
    }

    @Test func interruptWhenIdleIsNoop() {
        let r = TurnStatusReducer()
        #expect(r.interrupt() == nil)
    }
}
