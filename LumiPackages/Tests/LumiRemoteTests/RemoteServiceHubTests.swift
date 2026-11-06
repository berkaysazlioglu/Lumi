import Testing
import Foundation
@testable import LumiRemote
import LumiKit
import LumiTestSupport

// Bu Mac'in hub olarak paylaşılması (docs/design/08-mac-remote.md, Faz 2).

private let network = "network-token-A-1234567890"

private extension LumiPaths {
    /// Hub ayarlı remote.json (telefon kanalı `mobile` ile açılıp kapanır).
    static func hubDefaults(mobile: Bool = false, hubEnabled: Bool = true, networkToken: String = network) -> LumiPaths {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-remote-hub-test-\(UUID().uuidString)")
        let paths = LumiPaths(mode: .development, homeDirectory: home)
        try? paths.ensureDirectoriesExist()
        let json: [String: Any] = [
            "enabled": mobile, "relayUrl": "wss://test.invalid", "token": "tok",
            "networkToken": networkToken, "hubEnabled": hubEnabled,
            "hubId": "hub-0000-test", "hubName": "Build Mac",
        ]
        try? JSONSerialization.data(withJSONObject: json).write(to: paths.remoteFile)
        return paths
    }
}

@MainActor
private struct HubFixture {
    let mobile = FakeRelayConnection()
    let hub = FakeRelayConnection()
    let keychain = FakeKeychain()
    let term = FakeTerminalServicing()
    let service: RemoteService

    init(paths: LumiPaths = .hubDefaults(), password: String? = "doğru") async throws {
        if let password { try await RemoteHubSecrets(keychain: keychain).setPassword(password) }
        service = RemoteService(
            paths: paths, terminal: term, repos: FakeRepoService(),
            connection: mobile, hubConnection: hub,
            hubSecrets: RemoteHubSecrets(keychain: keychain),
            chatSource: FakeChatTranscriptSource(events: []), config: FakeConfigService())
    }

    func makeSession() -> (raw: String, id: TerminalID) {
        let meta = TerminalMeta(id: TerminalID(), name: "T", repoPath: "/repo", createdAt: Date())
        term.metas.append(meta)
        return (meta.id.description, meta.id)
    }

    /// Hub kanalına bağlanma isteği enjekte eder ve cevabını bekler.
    func attach(connectionId: String, password: String, controllerId: String = "ctrl-0001") async throws {
        let before = await hub.count(type: "attach_result")
        await hub.injectInbound(type: "attach_request", payload: [
            "requestId": "req-\(connectionId)-\(before)", "connectionId": connectionId,
            "controllerId": controllerId, "controllerName": "Laptop", "password": password,
        ])
        try await hub.waitForCount(type: "attach_result", atLeast: before + 1)
    }
}

@MainActor
struct RemoteServiceHubTests {
    @Test func hubChannelOpensWithNetworkIdentityAndKeyWhenReady() async throws {
        let f = try await HubFixture()
        await f.service.start()
        let hello = await f.hub.hello
        #expect(hello["role"] == "hub")
        #expect(hello["network"] == network)
        #expect(hello["hubId"] == "hub-0000-test")
        #expect(hello["name"] == "Build Mac")
        #expect((hello["hubKey"]?.count ?? 0) >= 16)
        // Telefon kanalı kapalıyken açılmaz.
        #expect(await f.mobile.startCount == 0)
        #expect(f.service.hasHubPassword)
        // hubKey kalıcıdır: yeniden başlatma aynı anahtarı kullanır.
        await f.service.restart()
        #expect(await f.hub.hello["hubKey"] == hello["hubKey"])
        f.service.stop()
    }

    @Test(arguments: [
        (hubEnabled: false, networkToken: network, password: "doğru" as String?),
        (hubEnabled: true, networkToken: "", password: "doğru" as String?),
        (hubEnabled: true, networkToken: network, password: nil as String?),
    ])
    func hubChannelStaysClosedWithoutSharingTokenOrPassword(
        hubEnabled: Bool, networkToken: String, password: String?
    ) async throws {
        let f = try await HubFixture(paths: .hubDefaults(hubEnabled: hubEnabled, networkToken: networkToken),
                                     password: password)
        await f.service.start()
        #expect(await f.hub.startCount == 0)
        #expect(f.service.hubState == .disconnected)
    }

    @Test func correctPasswordAcceptsAndListsController() async throws {
        let f = try await HubFixture()
        await f.service.start()
        try await f.attach(connectionId: "conn-1", password: "doğru")
        #expect(await f.hub.lastBool(type: "attach_result", key: "ok") == true)
        #expect(f.service.hubControllers == [RemoteHubController(id: "conn-1", name: "Laptop")])

        await f.hub.injectInbound(type: "controller_left", payload: ["from": "conn-1"])
        try await waitUntil { f.service.hubControllers.isEmpty }
        f.service.stop()
    }

    @Test func wrongPasswordIsRejectedAndRepeatedFailuresLock() async throws {
        let f = try await HubFixture()
        await f.service.start()
        for _ in 0..<HubAttemptLimiter.maxFailures {
            try await f.attach(connectionId: "conn-x", password: "yanlış")
            #expect(await f.hub.lastString(type: "attach_result", key: "error") == "wrong_password")
        }
        // Kilitliyken doğru şifre de reddedilir.
        try await f.attach(connectionId: "conn-x", password: "doğru")
        #expect(await f.hub.lastBool(type: "attach_result", key: "ok") == false)
        #expect(await f.hub.lastString(type: "attach_result", key: "error") == "locked")
        // Başka controller etkilenmez.
        try await f.attach(connectionId: "conn-y", password: "doğru", controllerId: "ctrl-0002")
        #expect(await f.hub.lastBool(type: "attach_result", key: "ok") == true)
        #expect(f.service.hubControllers.map(\.id) == ["conn-y"])
        f.service.stop()
    }

    @Test func broadcastsReachBothChannelsAndCommandResultOnlyTheAsker() async throws {
        let f = try await HubFixture(paths: .hubDefaults(mobile: true))
        await f.service.start()
        #expect(await f.mobile.startCount == 1)
        await f.hub.injectInbound(type: "welcome", payload: [:])
        try await f.hub.waitForSent(types: ["sessions"])
        try await f.mobile.waitForSent(types: ["sessions"])

        await f.hub.injectInbound(type: "command", payload: [
            "commandId": "c1", "action": "unknown_action", "from": "conn-1",
        ])
        try await f.hub.waitForSent(types: ["command_result"])
        #expect(await f.hub.lastStrings(type: "command_result")["to"] == "conn-1")
        #expect(await f.mobile.count(type: "command_result") == 0)
        f.service.stop()
    }

    @Test func terminalFeedRunsUntilTheLastWatcherLeaves() async throws {
        let f = try await HubFixture(paths: .hubDefaults(mobile: true))
        let session = f.makeSession()
        await f.service.start()

        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-2"])
        // İkinci abonelik akışı yeniden kurar; tek snapshot hub kanalındaki herkese gider.
        try await f.hub.waitForCount(type: "scrollback", atLeast: 1)

        // Telefonun aynı terminali chat modunda açması controller'ın aynasını kesmez.
        await f.mobile.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "mode": "chat"])
        await f.mobile.injectInbound(type: "unsubscribe", payload: ["sessionId": session.raw])
        await f.hub.injectInbound(type: "unsubscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        try await Task.sleep(for: .milliseconds(50))
        #expect(f.service.hasActiveSubscription(session.id))

        // Son izleyici ayrılınca (controller_left) akış kapanır.
        await f.hub.injectInbound(type: "controller_left", payload: ["from": "conn-2"])
        try await waitUntil { !f.service.hasActiveSubscription(session.id) }
        f.service.stop()
    }

    /// Aynı controller bir terminali hem ayna (terminal) hem okuma (chat) olarak izler;
    /// okumanın `unsubscribe{mode:chat}`'i aynayı koparmaz.
    @Test func chatReadDoesNotCutTheSameControllersMirror() async throws {
        let f = try await HubFixture()
        let session = f.makeSession()
        await f.service.start()
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        try await f.hub.waitForSent(types: ["scrollback"])
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "mode": "chat", "from": "conn-1"])
        await f.hub.injectInbound(type: "unsubscribe", payload: ["sessionId": session.raw, "mode": "chat", "from": "conn-1"])
        try await Task.sleep(for: .milliseconds(50))
        #expect(f.service.hasActiveSubscription(session.id))
        await f.hub.injectInbound(type: "unsubscribe", payload: ["sessionId": session.raw, "mode": "terminal", "from": "conn-1"])
        try await waitUntil { !f.service.hasActiveSubscription(session.id) }
        f.service.stop()
    }

    /// Controller'lar ekranı VT durumuyla alır (karar 143 ek); telefonun düz snapshot'ı değişmez.
    @Test func controllersGetScreenStateWhilePhoneKeepsPlainScrollback() async throws {
        let f = try await HubFixture(paths: .hubDefaults(mobile: true))
        let session = f.makeSession()
        f.term.scrollback = (Data("düz".utf8), 80, 24)
        f.term.screenState = (Data("\u{1B}[1;31mvt".utf8), 100, 30)
        await f.service.start()

        await f.mobile.injectInbound(type: "subscribe", payload: ["sessionId": session.raw])
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        try await f.hub.waitForSent(types: ["scrollback"])
        try await f.mobile.waitForSent(types: ["scrollback"])

        #expect(await f.hub.lastStrings(type: "scrollback")["data"] == Data("\u{1B}[1;31mvt".utf8).base64EncodedString())
        #expect(await f.hub.firstInt(type: "scrollback", key: "cols") == 100)
        #expect(await f.mobile.lastStrings(type: "scrollback")["data"] == Data("düz".utf8).base64EncodedString())
        #expect(await f.mobile.firstInt(type: "scrollback", key: "cols") == 80)
        f.service.stop()
    }

    /// Hub terminali boyut değiştirince controller'lara yeni boyutta snapshot gider;
    /// telefonun düz akışı etkilenmez (karar 143 ek).
    @Test func hubResizeResendsTheScreenStateToControllersOnly() async throws {
        let f = try await HubFixture(paths: .hubDefaults(mobile: true))
        let session = f.makeSession()
        f.term.screenState = (Data("vt".utf8), 100, 30)
        await f.service.start()
        await f.mobile.injectInbound(type: "subscribe", payload: ["sessionId": session.raw])
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        try await f.hub.waitForSent(types: ["scrollback"])
        try await f.mobile.waitForSent(types: ["scrollback"])

        try await f.mobile.waitForCount(type: "scrollback", atLeast: 2) // iki abonelik → telefonda iki kurulum
        let phoneSnapshots = await f.mobile.count(type: "scrollback")
        let hubSnapshots = await f.hub.count(type: "scrollback")
        f.term.emitMirrorSnapshot(session.id, data: Data("vt2".utf8), cols: 140, rows: 40)
        try await f.hub.waitForCount(type: "scrollback", atLeast: hubSnapshots + 1)
        #expect(await f.hub.lastInt(type: "scrollback", key: "cols") == 140)
        #expect(await f.hub.lastStrings(type: "scrollback")["data"] == Data("vt2".utf8).base64EncodedString())
        f.term.emitOutput(session.id, Data("x".utf8))
        try await f.mobile.waitForSent(types: ["data"])
        try await f.hub.waitForSent(types: ["data"])
        #expect(await f.mobile.count(type: "scrollback") == phoneSnapshots)
        f.service.stop()
    }

    /// İzlemeyen controller'a ve telefona terminal/chat içeriği gitmez; durum `sessions`'ta herkese
    /// gider (relay maliyeti, karar 143 ek).
    @Test func onlyWatchersReceiveTerminalAndChatContent() async throws {
        let f = try await HubFixture(paths: .hubDefaults(mobile: true))
        let session = f.makeSession()
        await f.service.start()
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        try await f.hub.waitForSent(types: ["scrollback"])
        f.term.emitOutput(session.id, Data("x".utf8))
        try await f.hub.waitForSent(types: ["data"])

        let targets = await f.hub.targets(types: ["scrollback", "data"])
        #expect(!targets.isEmpty)
        #expect(targets.allSatisfy { $0 == "conn-1" })
        #expect(await f.mobile.count(type: "scrollback") == 0)
        #expect(await f.mobile.count(type: "data") == 0)
        #expect(RemoteService.hubAudience("chat_status") == .chatWatchers)
        #expect(RemoteService.hubAudience("usage") == .nobody)
        #expect(RemoteService.hubAudience("sessions") == .everyone)
        f.service.stop()
    }

    /// `read_screen`: ekranın düz metni yalnız isteyen controller'a döner.
    @Test func readScreenRepliesWithPlainText() async throws {
        let f = try await HubFixture()
        let session = f.makeSession()
        f.term.scrollback = (Data("$ make build\nok\n\n\n".utf8), 80, 24)
        await f.service.start()

        await f.hub.injectInbound(type: "command", payload: [
            "commandId": "r1", "action": "read_screen", "sessionId": session.raw, "from": "conn-1",
        ])
        try await f.hub.waitForSent(types: ["command_result"])
        #expect(await f.hub.lastBool(type: "command_result", key: "ok") == true)
        #expect(await f.hub.lastStrings(type: "command_result")["to"] == "conn-1")
        #expect(await f.hub.lastStringMap(type: "command_result", key: "data")["text"] == "$ make build\nok\n")
        f.service.stop()
    }

    /// Controller'ın chat görünümünden gelen mesaj telefonunki gibi PTY'ye yazılır:
    /// önce metin, kısa beklemeyle ayrı bir Enter (karar 143 ek).
    @Test func controllerChatSendTypesIntoTheTerminal() async throws {
        let f = try await HubFixture()
        let session = f.makeSession()
        await f.service.start()
        await f.hub.injectInbound(type: "chat_send", payload: [
            "sessionId": session.raw, "text": "testleri koş", "from": "conn-1",
        ])
        try await waitUntil { f.term.writes.count == 2 }
        #expect(f.term.writes.map(\.1) == ["testleri koş", "\r"])
        f.service.stop()
    }

    @Test func hubDisconnectReleasesControllersAndTheirFeeds() async throws {
        let f = try await HubFixture()
        let session = f.makeSession()
        await f.service.start()
        try await f.attach(connectionId: "conn-1", password: "doğru")
        await f.hub.injectInbound(type: "subscribe", payload: ["sessionId": session.raw, "from": "conn-1"])
        try await f.hub.waitForSent(types: ["scrollback"])

        await f.hub.injectState(.disconnected)
        try await waitUntil { f.service.hubControllers.isEmpty && !f.service.hasActiveSubscription(session.id) }
        f.service.stop()
    }

    @Test func passwordChangeRevokesControllers() async throws {
        let f = try await HubFixture()
        await f.service.start()
        try await f.attach(connectionId: "conn-1", password: "doğru")
        try await f.service.setHubPassword("yeni")
        #expect(await f.hub.count(type: "revoke_controllers") == 1)
        #expect(f.service.hubControllers.isEmpty)
        // Yeni şifre geçerli, eskisi değil.
        try await f.attach(connectionId: "conn-2", password: "doğru")
        #expect(await f.hub.lastBool(type: "attach_result", key: "ok") == false)
        try await f.attach(connectionId: "conn-3", password: "yeni", controllerId: "ctrl-0003")
        #expect(await f.hub.lastBool(type: "attach_result", key: "ok") == true)
        f.service.stop()
    }

    @Test func renameUpdatesRelayWithoutReconnecting() async throws {
        let f = try await HubFixture()
        await f.service.start()
        await f.service.setHubName("Ofis Mac")
        #expect(await f.hub.lastStrings(type: "hub_update")["name"] == "Ofis Mac")
        #expect(await f.hub.startCount == 1)
        #expect(await f.hub.stopCount == 0)
        f.service.stop()
    }

    @Test func removingPasswordStopsSharing() async throws {
        let f = try await HubFixture()
        await f.service.start()
        try await f.service.removeHubPassword()
        #expect(!f.service.hasHubPassword)
        #expect(!f.service.currentConfig.hubEnabled)
        #expect(f.service.hubState == .disconnected)
    }

    @Test func joinNetworkValidatesTheToken() async throws {
        let f = try await HubFixture(paths: .hubDefaults(networkToken: ""))
        #expect(await f.service.joinNetwork("kısa") == false)
        #expect(await f.service.joinNetwork("  boşluk içeren token 123  ") == false)
        #expect(await f.service.joinNetwork("  \(network)\n") == true)
        #expect(f.service.currentConfig.networkToken == network)
        await f.service.leaveNetwork()
        #expect(f.service.currentConfig.networkToken.isEmpty)
        #expect(!f.service.currentConfig.hubEnabled)
        f.service.stop()
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("koşul 2 sn içinde sağlanmadı")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
