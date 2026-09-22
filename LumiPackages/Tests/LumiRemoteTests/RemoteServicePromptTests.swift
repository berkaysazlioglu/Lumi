import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

@Suite @MainActor struct RemoteServicePromptTests {
    private func hookEvent(_ kind: AgentHookEventKind, terminalID: TerminalID, tool: String? = nil,
                           input: String? = nil, useID: String? = nil) -> AgentHookEvent {
        AgentHookEvent(provider: .claude, terminalID: terminalID, kind: kind, agentID: nil,
                       teammateName: nil, toolName: tool, source: nil, trigger: nil,
                       isInterrupt: false, promptHead: nil, runningBackgroundAgentIDs: nil,
                       toolInput: input, toolUseID: useID)
    }

    @Test func permissionPromptEmittedThenResolvedByRespond() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let hooks = FakeAgentHookServer()
        let uuid = UUID()
        let meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        term.metas.append(meta)
        let sid = meta.id.description
        let id = TerminalID(raw: uuid)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []), hookEvents: { hooks.events() },
            config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForSent(types: ["chat_status"])

        hooks.emit(hookEvent(.permissionRequest, terminalID: id, tool: "Bash", input: #"{"command":"npm i"}"#, useID: "tu1"))
        try await conn.waitForCount(type: "prompt", atLeast: 1)
        #expect(await conn.lastString(type: "prompt", key: "kind") == "approval")
        #expect(await conn.lastString(type: "prompt", key: "state") == "pending")

        await conn.injectInbound(type: "prompt_respond",
            payload: ["sessionId": sid, "itemId": "tu1", "expectedRevision": 0, "optionId": "allow"])
        try await conn.waitForCount(type: "prompt", atLeast: 2)
        #expect(await conn.lastString(type: "prompt", key: "state") == "resolved")
        #expect(term.writtenInput[id] == Data([0x31]))
        svc.stop()
    }

    @Test func denyWritesEscape() async throws {
        let conn = FakeRelayConnection(); let term = FakeTerminalServicing(); let hooks = FakeAgentHookServer()
        let uuid = UUID()
        term.metas.append(TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo", createdAt: Date(), claudeSessionID: uuid.uuidString))
        let sid = TerminalID(raw: uuid).description; let id = TerminalID(raw: uuid)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []), hookEvents: { hooks.events() },
            config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForSent(types: ["chat_status"])
        hooks.emit(hookEvent(.permissionRequest, terminalID: id, tool: "Bash", input: "{}", useID: "tu9"))
        try await conn.waitForCount(type: "prompt", atLeast: 1)
        await conn.injectInbound(type: "prompt_respond", payload: ["sessionId": sid, "itemId": "tu9", "expectedRevision": 0, "optionId": "deny"])
        try await conn.waitForCount(type: "prompt", atLeast: 2)
        #expect(term.writtenInput[id] == Data([0x1b]))
        svc.stop()
    }

    @Test func multiSelectQuestionWritesFullPacedSequence() async throws {
        let conn = FakeRelayConnection(); let term = FakeTerminalServicing(); let hooks = FakeAgentHookServer()
        let uuid = UUID()
        term.metas.append(TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                       createdAt: Date(), claudeSessionID: uuid.uuidString))
        let sid = TerminalID(raw: uuid).description; let id = TerminalID(raw: uuid)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []), hookEvents: { hooks.events() },
            keystrokeScheduler: InstantScheduler(), config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForSent(types: ["chat_status"])
        hooks.emit(hookEvent(.preToolUse, terminalID: id, tool: "AskUserQuestion",
            input: #"{"questions":[{"question":"Pick","multiSelect":true,"options":[{"label":"A"},{"label":"B"}]}]}"#, useID: "q1"))
        try await conn.waitForCount(type: "prompt", atLeast: 1)
        #expect(await conn.lastBool(type: "prompt", key: "multiSelect") == true)

        // selections [0,1] → buildAskAnswerKeys → "1","2","\u{1b}[C","\r"
        await conn.injectInbound(type: "prompt_respond",
            payload: ["sessionId": sid, "itemId": "q1", "expectedRevision": 0, "selections": [["indices": [0, 1]]]])
        try await conn.waitForCount(type: "prompt", atLeast: 2)   // resolved
        let expected = Data([0x31, 0x32, 0x1b, 0x5b, 0x43, 0x0d])
        var ok = false
        for _ in 0..<200 { if term.writtenInput[id] == expected { ok = true; break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(ok)
        svc.stop()
    }
}

/// Test için ani-çalışan scheduler (pacing gecikmesi yok).
struct InstantScheduler: KeystrokeScheduling {
    func sleep(_ duration: Duration) async throws {}
}
