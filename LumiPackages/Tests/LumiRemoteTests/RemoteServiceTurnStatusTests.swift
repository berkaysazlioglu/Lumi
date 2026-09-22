import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

@Suite @MainActor struct RemoteServiceTurnStatusTests {

    // MARK: - Test helpers

    private func hookEvent(_ kind: AgentHookEventKind, terminalID: TerminalID,
                           tool: String? = nil) -> AgentHookEvent {
        AgentHookEvent(provider: .claude, terminalID: terminalID, kind: kind, agentID: nil,
                       teammateName: nil, toolName: tool, source: nil, trigger: nil,
                       isInterrupt: false, promptHead: nil, runningBackgroundAgentIDs: nil)
    }

    // MARK: - Tests

    /// Hook olayları abone olan bir chat session'a chat_status yaymalı.
    @Test func hookDrivenStatusReachesSubscriber() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let hooks = FakeAgentHookServer()

        // Chat session kur (claudeSessionID dolu olmalı)
        let uuid = UUID()
        let meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        term.metas.append(meta)
        let sid = meta.id.description
        let id = TerminalID(raw: uuid)

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { hooks.events() },
            turnClock: { Date(timeIntervalSince1970: 100) },
            config: FakeConfigService()
        )
        await svc.start()

        // (a) subscribe (chat) → idle snapshot chat_status gelir
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForCount(type: "chat_status", atLeast: 1)
        #expect(await conn.lastBool(type: "chat_status", key: "working") == false)

        // (b) userPromptSubmit → working=true, startedAtMs=100_000
        hooks.emit(hookEvent(.userPromptSubmit, terminalID: id))
        try await conn.waitForCount(type: "chat_status", atLeast: 2)
        #expect(await conn.lastBool(type: "chat_status", key: "working") == true)
        #expect(await conn.lastInt(type: "chat_status", key: "startedAtMs") == 100_000)

        // (c) preToolUse Bash → tool=Bash
        hooks.emit(hookEvent(.preToolUse, terminalID: id, tool: "Bash"))
        try await conn.waitForCount(type: "chat_status", atLeast: 3)
        #expect(await conn.lastString(type: "chat_status", key: "tool") == "Bash")

        // (d) stop → working=false
        hooks.emit(hookEvent(.stop, terminalID: id))
        try await conn.waitForCount(type: "chat_status", atLeast: 4)
        #expect(await conn.lastBool(type: "chat_status", key: "working") == false)

        svc.stop()
    }

    /// Abone olmayan session için chat_status yollanmamalı.
    @Test func noChatStatusForUnsubscribedSession() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let hooks = FakeAgentHookServer()

        let uuid = UUID()
        let meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        term.metas.append(meta)
        let id = TerminalID(raw: uuid)

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { hooks.events() },
            config: FakeConfigService()
        )
        await svc.start()

        // subscribe YOK — hook olayı üret
        hooks.emit(hookEvent(.userPromptSubmit, terminalID: id))

        // kısa settle sonrası hiç chat_status yollanmamalı
        try await conn.waitForNoSent(type: "chat_status", after: 0, for: .milliseconds(200))
        #expect(await conn.count(type: "chat_status") == 0)

        svc.stop()
    }
}

// MARK: - Restart dayanıklılığı (2026-09-17 cihaz bug'ı)

/// stop()→start() sonrası hook olayları HÂLÂ işlenmeli. Eski kod init'te tek
/// AsyncStream sakladığı için ikinci start ölü stream dinliyordu → turn-status
/// ve prompt kartları o process'te sonsuza dek kesiliyordu.
@Suite @MainActor struct RemoteServiceRestartTests {
    @Test func hookEventsSurviveServiceRestart() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let hooks = FakeAgentHookServer()
        let uuid = UUID()
        term.metas.append(TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                       createdAt: Date(), claudeSessionID: uuid.uuidString))
        let sid = TerminalID(raw: uuid).description
        let id = TerminalID(raw: uuid)
        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { hooks.events() },
            config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForSent(types: ["chat_status"])

        // Restart: stop fire-and-forget → disconnected state'ini bekle, sonra start.
        let states = svc.events()
        svc.stop()
        for await e in states { if case .stateChanged(.disconnected) = e { break } }
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForCount(type: "chat_status", atLeast: 2)

        // Ölü-stream bug'ı: restart SONRASI hook olayı prompt üretmeli.
        hooks.emit(AgentHookEvent(provider: .claude, terminalID: id, kind: .permissionRequest,
                                  agentID: nil, teammateName: nil, toolName: "Bash", source: nil,
                                  trigger: nil, isInterrupt: false, promptHead: nil,
                                  runningBackgroundAgentIDs: nil, toolInput: "{}", toolUseID: "tr1"))
        try await conn.waitForCount(type: "prompt", atLeast: 1)
        svc.stop()
    }
}
