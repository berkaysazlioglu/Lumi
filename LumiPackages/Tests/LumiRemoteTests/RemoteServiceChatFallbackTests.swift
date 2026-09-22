import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

/// Faz 2 sonrası / Karar 79 sonrası: non-claude terminal oturumları mirror-only kalır.
/// Claude provider terminal → transcript köprüsü (bkz. RemoteServiceClaudeChatTests).
/// Non-claude (bash/codex/shell/provider=nil) → boş chat + idle; feed kurulmaz.
///
/// DEĞİŞTİRİLEN TESTLER (Faz 2 söküm — karar 79 kapsamı dışında):
/// - chatSubscribeWithoutClaudeSessionEmitsChatUnavailablePlusFeed:
///     Eski: PTY feed de başlatılırdı. Yeni: feed BAŞLATILMAZ; sadece boş chat + idle.
/// - chatSubscribeAlsoStreamsFeed: KALDIRILDI (Faz 2 söküm).
///     Eski: chat mode terminale de feed başlatırdı. Yeni: terminal feed yalnız terminal mode'da.
/// - externalSessionResolvesViaLocatorThenStreamsChat: KALDIRILDI (Faz 2 söküm).
///     Eski: awaitTranscript/locator döngüsü. Yeni: chatSessions.snapshots nil → sessiz
///     (non-claude terminaller için); claude terminaller için RemoteServiceClaudeChatTests::T2.
@Suite @MainActor struct RemoteServiceChatFallbackTests {

    /// Terminal UUID'si ile mode=chat subscribe → boş chat + idle (feed yok).
    /// Eski test adı: chatSubscribeWithoutClaudeSessionEmitsChatUnavailablePlusFeed.
    /// Sökülen davranış: feed (scrollback/data) artık chat modu için kurulmaz.
    @Test func chatSubscribeForTerminalUUIDEmitsEmptyChatAndIdle() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let uuid = UUID()
        term.metas.append(TerminalMeta(id: TerminalID(raw: uuid), name: "T",
            repoPath: "/no/transcript/repo", createdAt: Date(), claudeSessionID: nil))
        let sid = TerminalID(raw: uuid).description
        // chatSessions no-op: snapshots her zaman nil → köprü kurulmaz, terminal path devreye girer
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        // Boş chat + idle status beklenir
        try await conn.waitForSent(types: ["chat", "chat_status"])
        // Feed kurulmaz (scrollback gelmez)
        try await conn.waitForNoSent(type: "scrollback", after: 0, for: .milliseconds(150))
        svc.stop()
    }

    /// Terminal modu (mode=terminal veya mode yoksa) → scrollback + data feed kurulur.
    /// Davranış söküm kapsamı dışında; regression koruma.
    @Test func terminalModeSubscribeStartsFeed() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let uuid = UUID()
        let id = TerminalID(raw: uuid)
        term.metas.append(TerminalMeta(id: id, name: "T", repoPath: "/repo",
            createdAt: Date(), claudeSessionID: "cs-1"))
        let sid = id.description
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "terminal"])
        try await conn.waitForSent(types: ["scrollback"])
        // Terminal çıktısı data olarak gelir
        term.emitOutput(id, Data("token".utf8))
        try await conn.waitForSent(types: ["data"])
        svc.stop()
    }
}
