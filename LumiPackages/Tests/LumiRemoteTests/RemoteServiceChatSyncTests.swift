import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

/// Karar 130: telefonun yeniden aboneliği ekrandaki sohbeti silmez.
@Suite @MainActor struct RemoteServiceChatSyncTests {

    private func claudeMeta(sessionID: String? = "cs-1") -> TerminalMeta {
        var m = TerminalMeta(id: TerminalID(), name: "claude", repoPath: "/tmp/r",
                             createdAt: Date(), claudeSessionID: sessionID)
        m.provider = .claude
        return m
    }

    private func message(_ id: String) -> ChatMessage {
        ChatMessage(id: id, role: .assistant, blocks: [.text("x", presentation: nil)],
                    timestampMs: nil, turnId: nil)
    }

    private func makeService(term: FakeTerminalServicing, conn: FakeRelayConnection,
                             source: FakeChatTranscriptSource,
                             locator: any TranscriptLocating = NoopTranscriptLocating()) -> RemoteService {
        RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
                      connection: conn, chatSource: source, hookEvents: { AsyncStream { _ in } },
                      transcriptLocator: locator, locatorRetryDelay: .milliseconds(1),
                      config: FakeConfigService())
    }

    @Test func claudeSubscribeSendsOnlyTheTranscriptSnapshot() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let meta = claudeMeta()
        term.metas.append(meta)
        let source = FakeChatTranscriptSource(events: [.snapshot([message("m1"), message("m2")])], keepOpen: true)
        let svc = makeService(term: term, conn: conn, source: source)
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": meta.id.description, "mode": "chat"])
        try await conn.waitForCount(type: "chat", atLeast: 1)
        try await conn.waitForNoSent(type: "chat", after: 1, for: .milliseconds(50))
        #expect(await conn.chatMessageCounts() == [2], "no empty placeholder before the snapshot")
        #expect(await conn.count(type: "chat_status") == 1, "one status frame, no unconditional idle")
        svc.stop()
    }

    @Test func nonClaudeSubscribeKeepsEmptyChatAndIdle() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let meta = TerminalMeta(id: TerminalID(), name: "bash", repoPath: "/tmp/b", createdAt: Date())
        term.metas.append(meta)
        let svc = makeService(term: term, conn: conn, source: FakeChatTranscriptSource(events: []))
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": meta.id.description, "mode": "chat"])
        try await conn.waitForSent(types: ["chat", "chat_status"])
        #expect(await conn.chatMessageCounts() == [0])
        #expect(await conn.lastBool(type: "chat_status", key: "working") == false)
        svc.stop()
    }

    @Test func externalTerminalWithoutTranscriptSendsEmptyChat() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let meta = claudeMeta(sessionID: nil)
        term.metas.append(meta)
        let svc = makeService(term: term, conn: conn, source: FakeChatTranscriptSource(events: []),
                              locator: FakeTranscriptLocating(returning: nil))
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": meta.id.description, "mode": "chat"])
        try await conn.waitForCount(type: "chat", atLeast: 1)
        #expect(await conn.chatMessageCounts() == [0], "the phone must not stay in Syncing…")
        svc.stop()
    }

    @Test func relayReconnectRestartsSubscribedTranscriptTail() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let meta = claudeMeta()
        term.metas.append(meta)
        let source = FakeChatTranscriptSource(events: [.snapshot([message("m1")])], keepOpen: true)
        let svc = makeService(term: term, conn: conn, source: source)
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": meta.id.description, "mode": "chat"])
        try await conn.waitForCount(type: "chat", atLeast: 1)
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForCount(type: "chat", atLeast: 2)
        #expect(source.requested.count == 2, "welcome re-creates the tail → fresh snapshot")
        svc.stop()
    }
}
