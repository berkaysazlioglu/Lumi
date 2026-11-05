import Testing
import Foundation
@testable import LumiRemote
import LumiKit
import LumiTestSupport

// Controller tarafı: directory, hub bağlantısı, şifre hatırlama, terminal aynası (docs/design/08, Faz 3).

private let network = "network-token-A-1234567890"
private let identity = RemoteControllerIdentity(controllerId: "me-install", name: "Laptop", ownHubId: "me-install")

@MainActor
private final class ControllerFixture {
    let keychain = FakeKeychain()
    private(set) var connections: [FakeRelayConnection] = []
    private(set) var service: RemoteControllerService!

    init() {
        service = RemoteControllerService(keychain: keychain) { [unowned self] in
            let connection = FakeRelayConnection()
            self.connections.append(connection)
            return connection
        }
    }

    var directory: FakeRelayConnection { connections[0] }
    var link: FakeRelayConnection { connections[1] }

    func configure() async throws {
        service.configure(relayUrl: "wss://test.invalid", networkToken: network, identity: identity)
        try await waitUntil { await (self.connections.first?.startCount ?? 0) == 1 }
    }

    func publishHubs(online: Bool = true) async {
        await directory.injectInbound(type: "hubs", payload: ["hubs": [
            ["hubId": "me-install", "name": "This Mac", "online": true],
            ["hubId": "build", "name": "Build Mac", "online": online],
        ]])
    }

    /// Hub'a bağlanır ve relay'in kabul `welcome`'ını enjekte eder.
    func connectAccepted(password: String? = "pw", remember: Bool = false) async throws {
        await service.connect(hubId: "build", password: password, remember: remember)
        await link.injectInbound(type: "welcome", payload: [
            "sessions": [["id": "s1", "repoName": "lumi", "status": "idle", "provider": "claude"]],
            "projects": [["name": "Lumi", "path": "/p/lumi", "checkouts": [["path": "/p/lumi", "title": "main", "agentIds": ["s1"]]]]],
            "others": [],
        ])
        try await waitUntil { self.service.linkState("build") == .connected }
    }

    /// Son gönderilen komutu cevaplar.
    func answerLastCommand(ok: Bool = true, sessionId: String? = nil, error: String? = nil,
                           data: [String: String]? = nil) async throws {
        try await link.waitForSent(types: ["command"])
        let commandId = try #require(await link.allStrings(type: "command").last?["commandId"])
        var payload: [String: Any] = ["commandId": commandId, "ok": ok]
        if let sessionId { payload["sessionId"] = sessionId }
        if let error { payload["error"] = error }
        if let data { payload["data"] = data }
        await link.injectInbound(type: "command_result", payload: payload)
    }
}

@MainActor
struct RemoteControllerServiceTests {
    @Test func directoryListsNetworkHubsExceptThisMac() async throws {
        let f = ControllerFixture()
        try await f.configure()
        #expect(await f.directory.hello == [
            "role": "controller", "network": network, "controllerId": "me-install", "name": "Laptop",
        ])
        await f.publishHubs()
        try await waitUntil { f.service.hubs.map(\.id) == ["build"] }
    }

    @Test func emptyNetworkTokenKeepsTheDirectoryClosed() async throws {
        let f = ControllerFixture()
        f.service.configure(relayUrl: "wss://test.invalid", networkToken: "  ", identity: identity)
        try await Task.sleep(for: .milliseconds(50))
        #expect(f.connections.isEmpty)
        #expect(f.service.directoryState == .disconnected)
    }

    @Test func connectingSendsThePasswordAndLoadsTheHubSnapshot() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        #expect(await f.link.attach == ["hubId": "build", "password": "pw"])
        #expect(await f.link.hello["role"] == "controller")
        let snapshot = try #require(f.service.snapshot("build"))
        #expect(snapshot.sessions.map(\.id) == ["s1"])
        #expect(snapshot.projects.first?.checkouts.first?.agentIds == ["s1"])
    }

    @Test func rememberedPasswordIsReusedAndForgottenWhenRejected() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted(password: "pw", remember: true)
        #expect(await f.service.hasRememberedPassword(hubId: "build"))

        f.service.disconnect(hubId: "build")
        try await waitUntil { f.service.linkState("build") == .disconnected }
        await f.service.connect(hubId: "build", password: nil, remember: false)
        try await waitUntil { await f.connections.count == 3 }
        #expect(await f.connections[2].attach["password"] == "pw")

        await f.connections[2].injectClosed(code: 4003, reason: "wrong_password")
        try await waitUntil { f.service.linkState("build") == .rejected(reason: "wrong_password") }
        try await waitUntil { await !f.service.hasRememberedPassword(hubId: "build") }
        // Reddedilen bağlantı yeniden denenmez.
        #expect(await f.connections[2].stopCount >= 1)
    }

    @Test func missingRememberedPasswordAsksForOne() async throws {
        let f = ControllerFixture()
        try await f.configure()
        await f.service.connect(hubId: "build", password: nil, remember: false)
        #expect(f.connections.count == 1)
    }

    @Test func hubGoingOfflineWaitsAndReconnectsWhenItReturns() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        await f.link.injectClosed(code: 4004, reason: "hub_offline")
        try await waitUntil { f.service.linkState("build") == .waitingForHub }

        await f.publishHubs(online: true)
        try await waitUntil { await f.link.startCount == 2 }
        #expect(await f.link.attach["password"] == "pw")
    }

    @Test func startSessionReturnsTheNewTerminalId() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        async let started = f.service.startSession(hubId: "build", checkoutPath: "/p/lumi", kind: .shell)
        try await f.answerLastCommand(sessionId: "s2")
        #expect(try await started == "s2")
        let command = try #require(await f.link.allStrings(type: "command").last)
        #expect(command["action"] == "start_session")
        #expect(command["kind"] == "shell")
    }

    @Test func refusedCommandThrowsTheHubsReason() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        let service = f.service!
        let closed = Task { try await service.closeSession(hubId: "build", sessionId: "s1") }
        try await f.answerLastCommand(ok: false, error: "session_not_found")
        await #expect(throws: RemoteControllerError.failed("session_not_found")) { try await closed.value }
    }

    @Test func commandsFailFastWhenNotConnected() async throws {
        let f = ControllerFixture()
        try await f.configure()
        await #expect(throws: RemoteControllerError.notConnected) {
            _ = try await f.service.startSession(hubId: "build", checkoutPath: "/p", kind: .shell)
        }
    }

    @Test func terminalMirrorSubscribesStreamsAndUnsubscribes() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        var stream: AsyncStream<RemoteTerminalChunk>? = f.service.terminalOutput(hubId: "build", sessionId: "s1")
        try await f.link.waitForSent(types: ["subscribe"])
        #expect(await f.link.lastStrings(type: "subscribe") == ["sessionId": "s1", "mode": "terminal"])

        await f.link.injectInbound(type: "scrollback", payload: RemoteProtocol.scrollbackPayload(
            sessionId: "s1", seq: 0, cols: 100, rows: 30, data: Data("hi".utf8)))
        var iterator = stream!.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == RemoteTerminalChunk(data: Data("hi".utf8), cols: 100, rows: 30, isSnapshot: true))

        // Klavye girişi sırayla gider.
        for byte in "abc".utf8 { f.service.sendInput(hubId: "build", sessionId: "s1", data: Data([byte])) }
        try await f.link.waitForCount(type: "input", atLeast: 3)
        let inputs = await f.link.allStrings(type: "input").compactMap { $0["data"] }.compactMap { Data(base64Encoded: $0) }
        #expect(inputs == [Data("a".utf8), Data("b".utf8), Data("c".utf8)])

        // Ayna kapanınca (akış bırakılınca) unsubscribe gider.
        iterator = AsyncStream<RemoteTerminalChunk> { $0.finish() }.makeAsyncIterator()
        stream = nil
        try await f.link.waitForSent(types: ["unsubscribe"])
    }

    @Test func claudeTerminalsAreReadFromTheirTranscript() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        let service = f.service!
        let read = Task { try await service.readTerminal(hubId: "build", sessionId: "s1") }
        try await f.link.waitForSent(types: ["subscribe"])
        #expect(await f.link.lastStrings(type: "subscribe") == ["sessionId": "s1", "mode": "chat"])
        await f.link.injectInbound(type: "chat", payload: RemoteProtocol.chatPayload(sessionId: "s1", messages: [
            ChatMessage(id: "m1", role: .assistant, blocks: [.text("Build done", presentation: nil)], timestampMs: nil, turnId: nil),
        ]))
        guard case .transcript(let messages) = try await read.value else {
            Issue.record("transcript bekleniyordu")
            return
        }
        #expect(messages.map(\.id) == ["m1"])
        try await f.link.waitForSent(types: ["unsubscribe"])
        #expect(await f.link.lastStrings(type: "unsubscribe") == ["sessionId": "s1", "mode": "chat"])
    }

    /// Ekran okuması `read_screen` komutuyla düz metin alır; açık aynanın aboneliğine dokunmaz.
    @Test func screenReadUsesTheReadScreenCommand() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        let service = f.service!
        await f.link.injectInbound(type: "sessions", payload: ["sessions": [["id": "sh", "repoName": "lumi", "status": "idle"]]])
        let mirror = service.terminalOutput(hubId: "build", sessionId: "sh")
        try await f.link.waitForSent(types: ["subscribe"])
        let read = Task { try await service.readTerminal(hubId: "build", sessionId: "sh") }
        try await f.answerLastCommand(data: ["text": "$ ls\nREADME.md\n"])
        #expect(try await read.value == .screen("$ ls\nREADME.md\n"))
        let command = try #require(await f.link.allStrings(type: "command").last)
        #expect(command["action"] == "read_screen")
        #expect(command["sessionId"] == "sh")
        #expect(await f.link.count(type: "subscribe") == 1)
        #expect(await f.link.count(type: "unsubscribe") == 0, "açık ayna varken abonelik bırakılmaz")
        _ = mirror
    }

    /// `read_screen`'i bilmeyen eski hub'da scrollback snapshot'ına düşülür.
    @Test func screenReadFallsBackToScrollbackOnOldHubs() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        let service = f.service!
        await f.link.injectInbound(type: "sessions", payload: ["sessions": [["id": "sh", "repoName": "lumi", "status": "idle"]]])
        let read = Task { try await service.readTerminal(hubId: "build", sessionId: "sh") }
        try await f.answerLastCommand(ok: false, error: "unknown_action")
        try await f.link.waitForSent(types: ["subscribe"])
        await f.link.injectInbound(type: "scrollback", payload: RemoteProtocol.scrollbackPayload(
            sessionId: "sh", seq: 0, cols: 80, rows: 24, data: Data("$ ls\n".utf8)))
        #expect(try await read.value == .screen("$ ls\n"))
    }

    /// Claude chat görünümü: chat aboneliği, gelen dört frame tipi, gönderim ve bırakış.
    @Test func chatViewStreamsTheHubsChatFramesAndAnswers() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        var stream: AsyncStream<RemoteChatEvent>? = f.service.chatEvents(hubId: "build", sessionId: "s1", afterId: "m9")
        try await f.link.waitForSent(types: ["subscribe"])
        #expect(await f.link.lastStrings(type: "subscribe") == ["sessionId": "s1", "mode": "chat", "afterId": "m9"])

        let reply = ChatMessage(id: "m10", role: .assistant, blocks: [.text("ok", presentation: nil)], timestampMs: nil, turnId: nil)
        await f.link.injectInbound(type: "chat_append", payload: RemoteProtocol.chatAppendPayload(sessionId: "s1", messages: [reply], afterId: "m9"))
        await f.link.injectInbound(type: "chat_status", payload: RemoteProtocol.chatStatusPayload(
            sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 5, tool: "Bash")))
        let prompt = ChatPrompt(itemId: "p1", revision: 2, kind: .approval, title: "Bash", detail: nil,
                                options: [], state: .pending, selectedOptionId: nil)
        await f.link.injectInbound(type: "prompt", payload: RemoteProtocol.promptPayload(sessionId: "s1", prompt: prompt))
        await f.link.injectInbound(type: "chat", payload: RemoteProtocol.chatPayload(sessionId: "other", messages: []))
        await f.link.injectInbound(type: "chat", payload: RemoteProtocol.chatPayload(sessionId: "s1", messages: [reply], hasEarlier: true))

        var iterator = stream!.makeAsyncIterator()
        var events: [RemoteChatEvent] = []
        for _ in 0..<4 { if let event = await iterator.next() { events.append(event) } }
        #expect(events == [
            .append([reply], afterId: "m9"),
            .status(ChatTurnStatus(working: true, startedAtMs: 5, tool: "Bash")),
            .prompt(prompt),
            .snapshot([reply], hasEarlier: true),
        ])

        f.service.sendChat(hubId: "build", sessionId: "s1", text: "devam")
        f.service.respondPrompt(hubId: "build", sessionId: "s1", itemId: "p1", revision: 2, answer: .option("yes"))
        f.service.respondPrompt(hubId: "build", sessionId: "s1", itemId: "q1", revision: 1,
                                answer: .selections([RemotePromptSelection(indices: [0, 2], other: "not")]))
        try await f.link.waitForSent(types: ["chat_send"])
        try await f.link.waitForCount(type: "prompt_respond", atLeast: 2)
        #expect(await f.link.lastStrings(type: "chat_send") == ["sessionId": "s1", "text": "devam"])
        let responses = await f.link.allStrings(type: "prompt_respond")
        #expect(responses.first == ["sessionId": "s1", "itemId": "p1", "optionId": "yes"])
        #expect(await f.link.firstInt(type: "prompt_respond", key: "expectedRevision") == 2)

        // Okuma açık chat'i koparmaz; görünüm kapanınca chat aboneliği bırakılır.
        let service = f.service!
        let read = Task { try await service.readTerminal(hubId: "build", sessionId: "s1") }
        try await f.link.waitForCount(type: "subscribe", atLeast: 2)
        await f.link.injectInbound(type: "chat", payload: RemoteProtocol.chatPayload(sessionId: "s1", messages: [reply]))
        _ = try await read.value
        try await Task.sleep(for: .milliseconds(30))
        #expect(await f.link.count(type: "unsubscribe") == 0)
        iterator = AsyncStream<RemoteChatEvent> { $0.finish() }.makeAsyncIterator()
        stream = nil
        try await f.link.waitForSent(types: ["unsubscribe"])
        #expect(await f.link.lastStrings(type: "unsubscribe") == ["sessionId": "s1", "mode": "chat"])
    }

    @Test func changingTheNetworkDropsOpenLinks() async throws {
        let f = ControllerFixture()
        try await f.configure()
        try await f.connectAccepted()
        f.service.configure(relayUrl: "wss://test.invalid", networkToken: "other-network-0987654321", identity: identity)
        try await waitUntil { f.service.linkState("build") == .disconnected }
        try await waitUntil { await f.connections.last?.hello["network"] == "other-network-0987654321" }
    }
}

@MainActor
private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !(await condition()) {
        guard Date() < deadline else {
            Issue.record("koşul 2 sn içinde sağlanmadı")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
