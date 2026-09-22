import Testing
import Foundation
@testable import LumiRemote
import LumiKit
import LumiTestSupport

@Suite("RemoteCommandHandler")
@MainActor
struct RemoteCommandHandlerTests {

    // MARK: - Terminal start_session (regression)

    @Test func startSessionTerminalSpawnsProcess() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, config: FakeConfigService())
        let result = await handler.handle([
            "action": "start_session",
            "repoPath": "/repo",
            "prompt": "merhaba",
            "commandId": "cmd-1"
        ])
        #expect(result.ok)
        #expect(term.spawnedMetas.last != nil)
    }

    @Test func startSessionBindsClaudeSessionID() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, config: FakeConfigService())
        _ = await handler.handle([
            "action": "start_session",
            "repoPath": "/repo",
            "prompt": "merhaba",
            "commandId": "cmd-1"
        ])
        let meta = term.spawnedMetas.last
        #expect(meta != nil)
        #expect(meta?.claudeSessionID != nil)   // chat modu bağlanabilsin
    }

    // MARK: - kind=chat start_session (karar 80: telefon chat'i de claude TERMİNALİ açar)

    /// Karar 80: telefon-başlatılan chat, başsız stream-json değil, masaüstünde de
    /// görünen bir claude TERMİNALİ olarak açılır (karar 79 birleşimi). sessionId =
    /// spawn edilen terminalin id'sidir (telefon subscribeChat için).
    @Test func startSessionKindChatSpawnsClaudeTerminal() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let chatSvc = FakeChatSessionService()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, chatSessions: chatSvc, config: FakeConfigService())
        let result = await handler.handle([
            "action": "start_session",
            "kind": "chat",
            "repoPath": "/repo",
            "commandId": "cmd-chat-1"
        ])
        #expect(result.ok)
        // Claude terminali spawn edildi (masaüstü grid'de görünsün)
        #expect(term.spawnedMetas.count == 1)
        #expect(term.spawnCalls.last?.repoPath == "/repo")
        #expect(term.spawnCalls.last?.command == "claude")
        // sessionId = spawn edilen terminalin id'si
        #expect(result.sessionId == term.spawnedMetas.last?.id.description)
        // Başsız stream-json chat oturumu OLUŞTURULMADI
        #expect(chatSvc.created.isEmpty)
    }

    @Test func startSessionKindChatWithPromptBakesIntoCommand() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, config: FakeConfigService())
        _ = await handler.handle([
            "action": "start_session",
            "kind": "chat",
            "repoPath": "/repo",
            "prompt": "Merhaba Claude",
            "commandId": "cmd-chat-2"
        ])
        // prompt komuta gömülür (claude '<prompt>'), terminal path'iyle aynı
        let cmd = term.spawnCalls.last?.command
        #expect(cmd?.hasPrefix("claude ") == true)
        #expect(cmd?.contains("Merhaba Claude") == true)
    }

    @Test func startSessionKindChatEmptyPromptSpawnsBareClaude() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, config: FakeConfigService())
        _ = await handler.handle([
            "action": "start_session",
            "kind": "chat",
            "repoPath": "/repo",
            "commandId": "cmd-chat-3"
        ])
        // prompt yok → çıplak claude
        #expect(term.spawnCalls.last?.command == "claude")
    }

    // MARK: - delete_session (chat oturumu)

    /// REGRESYON ("chatte silemiyorum"): chat oturumu terminal PTY kaydında yok;
    /// delete_session onu chatSessions.close ile kapatmalı, terminal.kill ile değil
    /// (aksi halde session_not_found dönüyordu).
    @Test func deleteSessionClosesChatSession() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let chatSvc = FakeChatSessionService()
        let meta = ChatSessionMeta(id: "cs-del-1", repoPath: "/repo", createdAt: Date())
        chatSvc.stub(meta: meta, snapshots: [])
        let handler = RemoteCommandHandler(terminal: term, trust: trust, chatSessions: chatSvc, config: FakeConfigService())
        // Bir stream-json chat oturumunu doğrudan seed'le (karar 80: start_session artık
        // terminal açar, chatSessions.create çağırmaz — bu test delete dalını izole eder).
        _ = await chatSvc.create(repoPath: "/repo")
        let result = await handler.handle([
            "action": "delete_session", "sessionId": "cs-del-1", "commandId": "c2"
        ])
        #expect(result.ok)
        #expect(chatSvc.closed == ["cs-del-1"])
    }

    /// Chat kaydında olmayan id → terminal yoluna düşer → session_not_found (davranış korunur).
    @Test func deleteSessionUnknownIdFallsThroughToTerminalNotFound() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let chatSvc = FakeChatSessionService()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, chatSessions: chatSvc, config: FakeConfigService())
        let result = await handler.handle([
            "action": "delete_session",
            "sessionId": "11111111-1111-1111-1111-111111111111",
            "commandId": "c3"
        ])
        #expect(!result.ok)
        #expect(result.error == "session_not_found")
        #expect(chatSvc.closed.isEmpty)
    }

    // MARK: - chat_send (via RemoteService frame router)
    // chat_send, RemoteService.handleInbound'da yönlendirilir; handler doğrudan
    // bu frame'i işlemez. Handler seviyesi için RemoteServiceChatBridgeTests kullanılır.
    // Burada handler'ın chat_send'i bilemediğini (unknown_action döneceğini) doğrular.
    @Test func chatSendIsHandledByRemoteServiceNotHandler() async throws {
        let term = FakeTerminalService()
        let trust = FakeClaudeWorkspaceTrust()
        let handler = RemoteCommandHandler(terminal: term, trust: trust, config: FakeConfigService())
        // chat_send bir "action" değil, "type"; handler bunu bilmez.
        let result = await handler.handle([
            "action": "chat_send",
            "sessionId": "some-id",
            "text": "test",
            "commandId": "cmd-chat-send"
        ])
        #expect(!result.ok)
        #expect(result.error == "unknown_action")
    }

    // MARK: - add_project

    @Test func addProjectAppendsFavorite() async throws {
        let config = FakeConfigService()
        let repos = FakeRepoService(repos: [Repo(name: "orca", path: "/p/orca", isGitRepo: true, source: .standalone)])
        let handler = RemoteCommandHandler(
            terminal: FakeTerminalService(), trust: FakeClaudeWorkspaceTrust(),
            repos: repos, config: config)

        let result = await handler.handle(["commandId": "c1", "action": "add_project", "path": "/p/orca"])
        #expect(result.ok == true)
        let saved = await config.config().sidebarProjectPaths
        #expect(saved.contains("/p/orca"))
    }

    @Test func addProjectRejectsUnknownRepo() async throws {
        let handler = RemoteCommandHandler(
            terminal: FakeTerminalService(), trust: FakeClaudeWorkspaceTrust(),
            repos: FakeRepoService(repos: []), config: FakeConfigService())
        let result = await handler.handle(["commandId": "c1", "action": "add_project", "path": "/nope"])
        #expect(result.ok == false)
        #expect(result.error == "unknown_repo")
    }

    @Test func addProjectIsIdempotent() async throws {
        let config = FakeConfigService()
        var cfg = AppConfig.defaults
        cfg.sidebarProjectPaths = ["/p/orca"]
        await config.seed(cfg)
        let repos = FakeRepoService(repos: [Repo(name: "orca", path: "/p/orca", isGitRepo: true, source: .standalone)])
        let handler = RemoteCommandHandler(
            terminal: FakeTerminalService(), trust: FakeClaudeWorkspaceTrust(),
            repos: repos, config: config)

        _ = await handler.handle(["commandId": "c2", "action": "add_project", "path": "/p/orca"])
        let saved = await config.config().sidebarProjectPaths
        #expect(saved.filter { $0 == "/p/orca" }.count == 1)
    }
}
