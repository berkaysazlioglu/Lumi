import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

/// Karar 79: macOS-başlatılan Claude terminalleri telefonda chat view'de görünür.
/// TDD — üç değişiklik için RED/GREEN testleri.
@Suite @MainActor struct RemoteServiceClaudeChatTests {

    // MARK: - Yardımcı

    /// Provider=claude TerminalMeta oluştur (provider sonradan set edilir).
    private func makeClaudeMeta(repoPath: String = "/tmp/r") -> TerminalMeta {
        var m = TerminalMeta(id: TerminalID(), name: "claude", repoPath: repoPath, createdAt: Date())
        m.provider = .claude
        return m
    }

    // MARK: - T1: sendSessions — Claude terminali kind:"chat" ile işaretlenir

    /// Claude provider'lı terminal → sessions frame'inde kind:"chat" görünmeli.
    /// Non-claude terminal → kind absent (nil).
    @Test func claudeTerminalMarkedAsChatKindInSessions() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()

        // Claude terminal
        let claudeMeta = makeClaudeMeta()
        term.metas.append(claudeMeta)

        // Non-claude terminal (provider nil)
        var bashMeta = TerminalMeta(id: TerminalID(), name: "bash", repoPath: "/tmp/b", createdAt: Date())
        bashMeta.provider = nil
        term.metas.append(bashMeta)

        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
                                connection: conn, chatSource: FakeChatTranscriptSource(events: []),
                                hookEvents: { AsyncStream { _ in } }, config: FakeConfigService())
        await svc.start()

        // welcome → sendSessions tetiklenir
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["sessions"])

        let kinds = await conn.sessionKinds()
        // Claude terminal "chat" olarak işaretlenmeli
        #expect(kinds.contains("chat"), "Claude terminali kind:chat ile işaretlenmeli, mevcut kinds: \(kinds)")
        // Toplam kind sayısı 1 olmalı (yalnızca claude terminali)
        #expect(kinds.count == 1, "Yalnızca claude terminali kind:chat taşımalı, kinds: \(kinds)")
        svc.stop()
    }

    // MARK: - T2: handleSubscribe — Claude terminali için transcript köprüsü kurulur

    /// mode=chat subscribe ile claude terminale abone olunca awaitTranscript çağrılır
    /// ve transcript'ten gelen mesajlar chat_append olarak iletilir.
    @Test func subscribeChatToClaudeTerminalBridgesTranscript() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()

        let claudeMeta = makeClaudeMeta()
        term.metas.append(claudeMeta)
        let sid = claudeMeta.id.description

        // FakeTranscriptLocating → "s1" sessionID döndürür
        // FakeChatTranscriptSource → .append([msg]) olayı yayar
        let msg = ChatMessage(
            id: "m1",
            role: .assistant,
            blocks: [.text("merhaba", presentation: nil)],
            timestampMs: nil,
            turnId: nil
        )
        let chatSrc = FakeChatTranscriptSource(events: [.append([msg])])
        let locator = FakeTranscriptLocating(returning: "s1")

        let svc = RemoteService(
            paths: .testDefaults(),
            terminal: term,
            repos: FakeRepoService(),
            connection: conn,
            chatSource: chatSrc,
            hookEvents: { AsyncStream { _ in } },
            transcriptLocator: locator,
            config: FakeConfigService()
        )
        await svc.start()

        await conn.injectInbound(type: "subscribe",
                                  payload: ["sessionId": sid, "mode": "chat"])

        // chat_append frame'i beklenir (transcript'ten köprülendi)
        try await conn.waitForCount(type: "chat_append", atLeast: 1)

        let texts = await conn.chatAppendTexts()
        #expect(texts.contains("merhaba"),
                "Transcript'ten köprülenen mesaj chat_append içinde 'merhaba' içermeli, texts: \(texts)")
        svc.stop()
    }

    /// Karar 80 regresyonu: taze telefon chat'i `--session-id` ile spawn edilir, yani
    /// oturumun transcript id'si BİLİNİR (`meta.claudeSessionID`). awaitTranscript bu
    /// bilinen id'yi kullanmalı; locator'ın max-by-modified sonucunu DEĞİL (o, repodaki
    /// ESKİ bir oturumu seçip telefonda bayat geçmiş gösteriyordu). Locator yalnız
    /// harici (id'siz) oturumlar için kalır.
    @Test func subscribeChatPrefersKnownClaudeSessionIDOverLocator() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()

        var claudeMeta = TerminalMeta(
            id: TerminalID(), name: "claude", repoPath: "/tmp/r",
            createdAt: Date(), claudeSessionID: "known-fresh-123")
        claudeMeta.provider = .claude
        term.metas.append(claudeMeta)
        let sid = claudeMeta.id.description

        let msg = ChatMessage(id: "m1", role: .assistant,
                              blocks: [.text("taze", presentation: nil)], timestampMs: nil, turnId: nil)
        let chatSrc = FakeChatTranscriptSource(events: [.append([msg])])
        // Locator ESKİ oturumu döndürür — kullanılmamalı.
        let locator = FakeTranscriptLocating(returning: "stale-old-999")

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: chatSrc,
            hookEvents: { AsyncStream { _ in } }, transcriptLocator: locator,
            config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForCount(type: "chat_append", atLeast: 1)

        // Bilinen id ile stream edilmeli, locator'ın eski id'siyle DEĞİL.
        #expect(chatSrc.requested.first?.sessionID == "known-fresh-123")
        #expect(chatSrc.requested.allSatisfy { $0.sessionID != "stale-old-999" })
        svc.stop()
    }

    // MARK: - T3a: handleChatSend — terminal PTY'ye yazar (stream-json oturumu yoksa)

    /// chat_send gelen id bir stream-json chat oturumuna ait değilse ve terminal ID ise
    /// terminal PTY'sine önce metin, settle sonrası AYRI bir CR yazılmalıdır — birleşik
    /// `text\r` Claude TUI'sinde paste ingest bitmeden Enter olarak yutuluyor ve submit
    /// tetiklenmiyordu (telefon terminal yolu paritesi: text → settle → CR). Regresyon:
    /// birleşik yazımda mesaj composer'a yapışıyor, submit bir sonraki mesaja sarkıyordu.
    @Test func chatSendToTerminalIdWritesTextThenSeparateCR() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()

        let claudeMeta = makeClaudeMeta()
        term.metas.append(claudeMeta)
        let sid = claudeMeta.id.description

        // chatSessions: boş list() → stream-json oturumu yok
        let chatSvc = FakeChatSessionService()

        let svc = RemoteService(
            paths: .testDefaults(),
            terminal: term,
            repos: FakeRepoService(),
            connection: conn,
            chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } },
            keystrokeScheduler: InstantScheduler(),   // settle'ı anında geç
            chatSessions: chatSvc,
            config: FakeConfigService()
        )
        await svc.start()

        await conn.injectInbound(type: "chat_send",
                                  payload: ["sessionId": sid, "text": "merhaba"])

        let tid = claudeMeta.id
        // İki ayrı yazım gelene kadar bekle (metin + CR).
        var writtenTexts: [String] = []
        for _ in 0..<200 {
            writtenTexts = term.writes.filter { $0.0 == tid }.map { $0.1 }
            if writtenTexts.count >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(writtenTexts == ["merhaba", "\r"],
                "Metin ve CR ayrı yazılmalı (text → settle → CR), writtenTexts: \(writtenTexts)")
        #expect(!writtenTexts.contains("merhaba\r"),
                "Birleşik 'merhaba\\r' yazılmamalı — TUI submit'i yutuyor.")
        svc.stop()
    }

    // MARK: - T3b: handleChatSend — stream-json oturumu varsa chatSessions.send çağrılır

    /// chat_send id, chatSessions.list()'te varsa PTY'ye değil chatSessions.send'e iletilmeli.
    @Test func chatSendToStreamJsonSessionCallsChatSessionsSend() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()

        let chatSvc = FakeChatSessionService()
        // Bir stream-json chat oturumu oluştur (id: "cs-active")
        chatSvc.stub(meta: ChatSessionMeta(id: "cs-active", repoPath: "/repo", createdAt: Date()),
                     snapshots: [])
        _ = await chatSvc.create(repoPath: "/repo")  // listeye ekle

        let svc = RemoteService(
            paths: .testDefaults(),
            terminal: term,
            repos: FakeRepoService(),
            connection: conn,
            chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } },
            chatSessions: chatSvc,
            config: FakeConfigService()
        )
        await svc.start()

        await conn.injectInbound(type: "chat_send",
                                  payload: ["sessionId": "cs-active", "text": "selam"])

        // Kısa bekle (chatSessions.send async ama fake hemen tamamlanır)
        try await Task.sleep(for: .milliseconds(50))

        #expect(chatSvc.sentText.map(\.text).contains("selam"),
                "Stream-json oturumuna chat_send → chatSessions.send çağrılmalı")
        // PTY'ye yazılmamalı
        #expect(term.writes.isEmpty,
                "Stream-json oturum id'si için PTY'ye yazılmamalı")
        svc.stop()
    }
}
