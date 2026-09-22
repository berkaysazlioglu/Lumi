import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

@Suite @MainActor struct RemoteServiceChatBridgeTests {
    /// Final review #1 regresyonu: start_session kind=chat sonrası chat oturumu
    /// `sessions` broadcast'ine kind:"chat" ile eklenmeli (yoksa telefon submitText'i
    /// PTY'ye düşürür → ikinci mesaj ölür).
    @Test func startChatCommandBroadcastsSessionWithKindChat() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        chatSvc.stub(meta: ChatSessionMeta(id: "cs-created", repoPath: "/repo",
                                           createdAt: Date(timeIntervalSince1970: 0)), snapshots: [])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "command",
            payload: ["commandId": "c1", "action": "start_session", "repoPath": "/repo", "kind": "chat"])
        try await conn.waitForSent(types: ["command_result", "sessions"])
        #expect(await conn.sessionKinds().contains("chat"))
        svc.stop()
    }


    // MARK: - Köprü diff: snapshot/append/chat_status

    /// Snapshot dizisi: boş → streaming → mesajlı → streaming + ek mesaj.
    /// Beklenen frame'ler: chat_status (streaming), chat (ilk mesajlar), chat_append (ek mesaj).
    @Test func chatSessionSubscribeBridgesSnapshotsToFrames() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs1", repoPath: "/repo", createdAt: Date())
        let m1 = ChatMessage(id: "m1", role: .assistant, blocks: [.text("Selam", presentation: nil)], timestampMs: nil, turnId: "m1")
        let m2 = ChatMessage(id: "m2", role: .user, blocks: [.text("Devam", presentation: nil)], timestampMs: nil, turnId: "m2")
        chatSvc.stub(meta: meta, snapshots: [
            ChatJournalState(),                                                  // boş: hiç frame yok
            { var s = ChatJournalState(); s.streamingText = "Sel"; s.turnActive = true; return s }(), // → chat_status
            { var s = ChatJournalState(); s.messages = [m1]; return s }(),       // → chat (ilk mesaj)
            { var s = ChatJournalState(); s.messages = [m1, m2]; return s }(),   // → chat_append (ek mesaj)
        ])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs1", "mode": "chat"])
        // Tüm üç frame tipi beklenir:
        try await conn.waitForSent(types: ["chat_status", "chat", "chat_append"])
        svc.stop()
    }

    // MARK: - İçerik güncellemesi (aynı id, büyüyen metin) yeniden gönderilir

    /// KRİTİK (vanish kök nedeni): partial assistant snapshot'ları aynı id ile büyür.
    /// Yalnız yeni id göndermek güncellemeleri düşürüyordu → canlıda bayat/kısa mesaj,
    /// reopen düzeltiyordu. Değişen mesaj chat_append ile YENİDEN gönderilmeli.
    @Test func updatedMessageContentReemittedAsChatAppend() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs-upd", repoPath: "/repo", createdAt: Date())
        let partial = ChatMessage(id: "m1", role: .assistant,
                                  blocks: [.text("Sel", presentation: nil)], timestampMs: nil, turnId: "m1")
        let full = ChatMessage(id: "m1", role: .assistant,
                               blocks: [.text("Selam dünya, nasılsın", presentation: nil)], timestampMs: nil, turnId: "m1")
        chatSvc.stub(meta: meta, snapshots: [
            { var s = ChatJournalState(); s.messages = [partial]; return s }(),  // → chat (ilk)
            { var s = ChatJournalState(); s.messages = [full]; return s }(),     // → chat_append (güncelleme)
        ])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs-upd", "mode": "chat"])
        try await conn.waitForSent(types: ["chat", "chat_append"])
        #expect(await conn.chatAppendTexts().contains("Selam dünya, nasılsın"),
                "aynı id'nin güncellenmiş içeriği chat_append ile yeniden gönderilmeli")
        svc.stop()
    }

    // MARK: - İlk mesaj snapshot olarak `chat` frame'i gönderir

    @Test func firstMessageEmittedAsChatSnapshot() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs2", repoPath: "/repo", createdAt: Date())
        let msg = ChatMessage(id: "m1", role: .assistant,
                              blocks: [.text("Merhaba", presentation: nil)],
                              timestampMs: nil, turnId: "m1")
        var withMsg = ChatJournalState()
        withMsg.messages = [msg]
        chatSvc.stub(meta: meta, snapshots: [withMsg])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs2", "mode": "chat"])
        try await conn.waitForSent(types: ["chat"])
        // chat_append bu sefer gelmemeli (tek snapshot)
        try await conn.waitForNoSent(type: "chat_append", after: 0, for: .milliseconds(100))
        svc.stop()
    }

    // MARK: - Sonraki yeni mesaj `chat_append` olarak gelir

    @Test func subsequentNewMessageEmittedAsChatAppend() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs3", repoPath: "/repo", createdAt: Date())
        let msg1 = ChatMessage(id: "m1", role: .assistant,
                               blocks: [.text("A", presentation: nil)],
                               timestampMs: nil, turnId: "m1")
        let msg2 = ChatMessage(id: "m2", role: .user,
                               blocks: [.text("B", presentation: nil)],
                               timestampMs: nil, turnId: "m2")
        var s1 = ChatJournalState(); s1.messages = [msg1]
        var s2 = ChatJournalState(); s2.messages = [msg1, msg2]
        chatSvc.stub(meta: meta, snapshots: [s1, s2])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs3", "mode": "chat"])
        try await conn.waitForSent(types: ["chat", "chat_append"])
        svc.stop()
    }

    // MARK: - streamingText değişince `chat_status` frame'i gelir

    @Test func streamingTextChangeTriggersChatStatus() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs4", repoPath: "/repo", createdAt: Date())
        var active = ChatJournalState(); active.streamingText = "düşünüyorum"; active.turnActive = true
        chatSvc.stub(meta: meta, snapshots: [active])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs4", "mode": "chat"])
        try await conn.waitForSent(types: ["chat_status"])
        let working = await conn.lastBool(type: "chat_status", key: "working")
        #expect(working == true)
        svc.stop()
    }

    // MARK: - Bilinen olmayan sessionId → köprü kurulmaz, terminal modu aktif olmaz

    @Test func unknownChatSessionIdDoesNotBridgeOrStartFeed() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        // stub yok: snapshots nil döndürür
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        // Bu bir UUID değil, chat oturumu da yok → mode=chat, ama UUID formatı da yanlış
        // Asıl case: geçerli bir UUID ama chatSvc'de yok → terminal yok, sessizce geç
        // (subscribe guard: terminalID(from:) nil döner için non-UUID format kullan)
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "not-a-uuid", "mode": "chat"])
        try await conn.waitForNoSent(type: "chat", after: 0, for: .milliseconds(150))
        svc.stop()
    }

    // MARK: - Chat oturumu abone iptal edilince task temizlenir

    @Test func unsubscribeCancelsChatSubscription() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs5", repoPath: "/repo", createdAt: Date())
        chatSvc.stub(meta: meta, snapshots: [ChatJournalState()])
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs5", "mode": "chat"])
        // Subscribe sonrası köprü task'ı aktif olmalı
        try await Task.sleep(for: .milliseconds(50))
        #expect(await svc.hasActiveChatBridgeTask("cs5") == true)
        await conn.injectInbound(type: "unsubscribe", payload: ["sessionId": "cs5"])
        // Unsubscribe sonrası köprü task'ı iptal edilmiş olmalı
        try await Task.sleep(for: .milliseconds(50))
        #expect(await svc.hasActiveChatBridgeTask("cs5") == false)
        svc.stop()
    }

    // MARK: - İlk snapshot boş olsa da chat frame yayılır (Fix I-2)

    @Test func chatSessionSubscribeEmitsInitialChatFrameEvenWhenEmpty() async throws {
        let conn = FakeRelayConnection()
        let chatSvc = FakeChatSessionService()
        chatSvc.stub(meta: ChatSessionMeta(id: "cs9", repoPath: "/repo", createdAt: Date()),
                     snapshots: [ChatJournalState()])   // yalnızca boş snapshot
        let svc = RemoteService(paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, chatSessions: chatSvc, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": "cs9", "mode": "chat"])
        // Boş olsa da ilk chat snapshot frame'i gelmeli
        try await conn.waitForSent(types: ["chat"])
        svc.stop()
    }
}
