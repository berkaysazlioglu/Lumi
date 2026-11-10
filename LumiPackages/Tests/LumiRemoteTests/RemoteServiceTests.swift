import Testing
import Foundation
import AppKit
@testable import LumiRemote
import LumiKit
import LumiTestSupport

// MARK: - Test paths helper

extension LumiPaths {
    /// Her çağrıda benzersiz geçici configDir + enabled=true remote.json.
    /// `start()` guard'ı `enabled` ister; token boşsa ensureToken üretir.
    static func testDefaults() -> LumiPaths {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-remote-test-\(UUID().uuidString)")
        let paths = LumiPaths(mode: .development, homeDirectory: home)
        try? paths.ensureDirectoriesExist()
        let json = "{\"enabled\":true,\"relayUrl\":\"wss://test.invalid\",\"token\":\"tok\",\"serverToken\":\"lrs_test-token\"}"
        try? json.data(using: .utf8)!.write(to: paths.remoteFile)
        return paths
    }
}

// MARK: - FakeRelayConnection

/// Gönderilenleri kaydeder, inbound mesajlarını enjekte eder.
final actor FakeRelayConnection: RelayConnecting {
    private var continuation: AsyncStream<RelayInbound>.Continuation?
    private(set) var sent: [(type: String, payload: [String: Any])] = []

    /// Son `start`'ın hello'sundaki string alanlar ve start/stop sayıları (hub testleri).
    private(set) var hello: [String: String] = [:]
    private(set) var startCount = 0
    private(set) var stopCount = 0

    /// Son `start`'ın sunucusu (karar 146 — adres + server token'ı).
    private(set) var endpoint: RelayEndpoint?

    func start(endpoint: RelayEndpoint, hello: [String: Any]) {
        self.endpoint = endpoint
        self.hello = hello.compactMapValues { $0 as? String }
        self.attach = (hello["attach"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        startCount += 1
    }
    func stop() { stopCount += 1 }

    /// Test API — relay'in soketi kapatmasını enjekte et (kapanış kodu + neden).
    func injectClosed(code: Int, reason: String?) {
        continuation?.yield(.closed(code: code, reason: reason))
        continuation?.yield(.stateChanged(.disconnected))
    }

    /// Test API — sunucunun kalıcı reddini enjekte et (karar 146).
    func injectRejected(_ issue: RemoteServerIssue) {
        continuation?.yield(.stateChanged(.disconnected))
        continuation?.yield(.rejected(issue))
    }

    /// Test API — sunucunun ağ reddini enjekte et (4006, karar 147; bağlantı denemeyi sürdürür).
    func injectBlocked(_ issue: RemoteServerIssue) {
        continuation?.yield(.stateChanged(.disconnected))
        continuation?.yield(.blocked(issue))
    }

    /// Son `start`'ın hello'sundaki `attach` sözlüğünün string alanları.
    private(set) var attach: [String: String] = [:]

    /// Belirli tipteki tüm mesajların string alanları, gönderim sırasıyla.
    func allStrings(type: String) -> [[String: String]] {
        sent.filter { $0.type == type }.map { $0.payload.compactMapValues { $0 as? String } }
    }

    /// Test API — bağlantı durumu olayını enjekte et.
    func injectState(_ state: RemoteConnectionState) {
        continuation?.yield(.stateChanged(state))
    }

    /// Belirli tipteki son mesajın payload'ındaki string alanlar.
    func lastStrings(type: String) -> [String: String] {
        (sent.last { $0.type == type }?.payload ?? [:]).compactMapValues { $0 as? String }
    }

    func send(type: String, payload: [String: Any]) {
        sent.append((type, payload))
    }

    /// Belirli tipteki son mesajın iç içe string sözlüğü (ör. `command_result.data`).
    func lastStringMap(type: String, key: String) -> [String: String] {
        sent.last { $0.type == type }?.payload[key] as? [String: String] ?? [:]
    }

    func inbound() -> AsyncStream<RelayInbound> {
        let (stream, continuation) = AsyncStream.makeStream(of: RelayInbound.self)
        self.continuation = continuation
        return stream
    }

    /// Test API — inbound mesajı enjekte et.
    func injectInbound(type: String, payload: [String: Any]) {
        continuation?.yield(.message(type: type, payload: payload))
    }

    /// Belirli tipteki ilk mesajın string alanı (Sendable sınır-güvenli).
    func firstString(type: String, key: String) -> String? {
        sent.first { $0.type == type }?.payload[key] as? String
    }

    /// Belirli tipteki ilk mesajın Int alanı.
    func firstInt(type: String, key: String) -> Int? {
        sent.first { $0.type == type }?.payload[key] as? Int
    }

    /// `repos` mesajının payload'ındaki repo adları (Sendable sınır-güvenli).
    func repoNames() -> [String] {
        guard let payload = sent.first(where: { $0.type == "repos" })?.payload,
              let list = payload["repos"] as? [[String: String]] else { return [] }
        return list.compactMap { $0["name"] }
    }

    func count(type: String) -> Int {
        sent.filter { $0.type == type }.count
    }

    /// Verilen tiplerdeki frame'lerin `to` alanları (hedefsizde nil).
    func targets(types: Set<String>) -> [String?] {
        sent.filter { types.contains($0.type) }.map { $0.payload["to"] as? String }
    }

    /// Tüm `chat_append` frame'lerindeki mesaj metin bloklarının düz listesi
    /// (içerik-güncelleme testi; Sendable [String] döner).
    func chatAppendTexts() -> [String] {
        sent.filter { $0.type == "chat_append" }
            .flatMap { ($0.payload["messages"] as? [[String: Any]]) ?? [] }
            .flatMap { ($0["blocks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["text"] as? String }
    }

    func sentTypes() -> [String] { sent.map { $0.type } }

    /// Son `chat_append` frame'inin mesaj kimlikleri.
    func lastAppendIds() -> [String] {
        let messages = sent.last { $0.type == "chat_append" }?.payload["messages"] as? [[String: Any]] ?? []
        return messages.compactMap { $0["id"] as? String }
    }

    /// Her `chat` frame'inin mesaj sayısı, gönderim sırasıyla.
    func chatMessageCounts() -> [Int] {
        sent.filter { $0.type == "chat" }.map { ($0.payload["messages"] as? [[String: Any]])?.count ?? -1 }
    }

    /// Gönderilen `sessions` frame'lerindeki meta `kind` değerleri (Sendable [String]
    /// döner — actor sınırından [String: Any] geçirmemek için).
    func sessionKinds() -> [String] {
        sent.filter { $0.type == "sessions" }
            .flatMap { ($0.payload["sessions"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["kind"] as? String }
    }

    /// Verilen tüm tipler gönderilene kadar (kısa timeout) bekler.
    func waitForSent(types: [String]) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let have = Set(sent.map { $0.type })
            if types.allSatisfy({ have.contains($0) }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FakeError.timeout("sent types \(types), have \(sent.map { $0.type })")
    }

    func waitForNoSent(type: String, after count: Int, for duration: Duration) async throws {
        try await Task.sleep(for: duration)
        let got = sent.filter { $0.type == type }.count
        if got > count {
            throw FakeError.timeout("expected no more '\(type)' after \(count), got \(got)")
        }
    }

    /// Son 'sessions' frame'inde verilen id'nin `awaitingDecision` değeri (yoksa nil).
    func lastSessionAwaitingDecision(id: String) -> Bool? {
        guard let payload = sent.last(where: { $0.type == "sessions" })?.payload,
              let list = payload["sessions"] as? [[String: Any]] else { return nil }
        return list.first { $0["id"] as? String == id }?["awaitingDecision"] as? Bool
    }

    func lastBool(type: String, key: String) -> Bool? { sent.last { $0.type == type }?.payload[key] as? Bool }
    func lastInt(type: String, key: String) -> Int? { sent.last { $0.type == type }?.payload[key] as? Int }
    func lastString(type: String, key: String) -> String? { sent.last { $0.type == type }?.payload[key] as? String }
    func waitForCount(type: String, atLeast n: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if sent.filter({ $0.type == type }).count >= n { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FakeError.timeout("expected >= \(n) '\(type)', have \(count(type: type))")
    }

    enum FakeError: Error { case timeout(String) }
}

// MARK: - FakeTerminalServicing

@MainActor
final class FakeTerminalServicing: TerminalServicing {
    private let broadcaster = EventBroadcaster<TerminalEvent>()
    private var outputBroadcasters: [TerminalID: EventBroadcaster<Data>] = [:]

    var metas: [TerminalMeta] = []
    var scrollback: (data: Data, cols: Int, rows: Int) = (Data(), 80, 24)
    private(set) var writtenInput: [TerminalID: Data] = [:]
    private(set) var writes: [(TerminalID, String)] = []
    private(set) var subscribedIDs: [TerminalID] = []
    private var inputContinuations: [AsyncStream<Void>.Continuation] = []

    var terminals: [TerminalMeta] { metas }

    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        // Üretim taklidi (TerminalSessionManager): provider spawn anında launch
        // komutundan sentaks olarak çıkarılır ("claude …" → .claude). Karar 80'de
        // telefon chat'i bir claude terminali açtığı için sendSessions'ın kind:"chat"
        // işaretlemesi buna bağlı.
        var meta = TerminalMeta(id: TerminalID(), name: "T", repoPath: repoPath, createdAt: Date())
        meta.provider = AgentProvider.detect(launchCommand: command)
        metas.append(meta)
        broadcaster.send(.spawned(meta))
        return meta
    }

    func spawn(repoPath: String, task: String?, command: String?,
               environment: [String: String]) throws -> TerminalMeta {
        try spawn(repoPath: repoPath, task: task, command: command)
    }

    func write(id: TerminalID, text: String) throws {
        writes.append((id, text))
        for c in inputContinuations { c.yield(()) }
    }
    func kill(id: TerminalID) throws {}
    func killAll() {}
    func resize(id: TerminalID, cols: Int, rows: Int) {}
    func setFocused(_ id: TerminalID?) {}
    func setWindowFocused(_ focused: Bool) {}
    func setMaxTerminals(_ n: Int) {}
    func events() -> AsyncStream<TerminalEvent> { broadcaster.stream() }
    func outputStream(id: TerminalID) -> AsyncStream<String>? { nil }

    // Yeni main protokol üyeleri (test için no-op).
    func processID(for id: TerminalID) -> Int32? { nil }
    func setSurfaceState(_ state: TerminalSurfaceState, for id: TerminalID) {}
    func setSurfaceState(_ state: TerminalSurfaceState, in sessionID: String?) {}
    func setAgentHookEndpoint(_ endpoint: AgentHookEndpoint?) {}
    func setLaunchEnvironment(_ environment: [String: String], for provider: AgentProvider) {}
    func setClaudePluginDirectories(_ paths: [String]) {}
    func applyAgentHookEvent(_ event: AgentHookEvent) {}
    func shutdown() {}
    func applyFont(_ font: NSFont) {}
    func applyCursor(shape: TerminalCursorShape, blink: Bool) {}
    func applyLinkActions(enabled: Bool) {}

    func subscribeOutput(_ id: TerminalID) -> AsyncStream<Data> {
        subscribedIDs.append(id)
        return outputBroadcaster(for: id).stream()
    }

    func writeInput(_ data: Data, to id: TerminalID) {
        writtenInput[id, default: Data()].append(data)   // biriktirir (paced çok-grup için)
        for c in inputContinuations { c.yield(()) }
    }

    func serializeScrollback(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int) {
        scrollback
    }

    /// Controller kanalının VT snapshot'ı; nil → düz snapshot (protokol varsayılanı).
    var screenState: (data: Data, cols: Int, rows: Int)?

    func serializeScreenState(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int) {
        screenState ?? scrollback
    }

    // MARK: Test API

    func emitOutput(_ id: TerminalID, _ data: Data) {
        outputBroadcaster(for: id).send(data)
    }

    func emit(_ event: TerminalEvent) { broadcaster.send(event) }

    /// writeInput çağrısı gelene kadar bekler.
    func waitForInput() async throws {
        if !writtenInput.isEmpty { return }
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        inputContinuations.append(continuation)
        if !writtenInput.isEmpty { return }
        for await _ in stream { return }
    }

    /// write(id:text:) çağrısı gelene kadar bekler (PTY metin yazımı için).
    func waitForWrite() async throws {
        if !writes.isEmpty { return }
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        inputContinuations.append(continuation)
        if !writes.isEmpty { return }
        for await _ in stream { return }
    }

    /// "Yazan kazanır" çağrıları (karar 143 ek): `nil` = yerel boyuta dönüş.
    private(set) var remoteGrids: [(id: TerminalID, grid: TerminalGrid?)] = []
    func setRemoteGrid(_ id: TerminalID, grid: TerminalGrid) { remoteGrids.append((id, grid)) }
    func clearRemoteGrid(_ id: TerminalID) { remoteGrids.append((id, nil)) }
    func remoteGridHistory(_ id: TerminalID) -> [TerminalGrid?] {
        remoteGrids.filter { $0.id == id }.map(\.grid)
    }

    /// Hub emülatörü boyut değiştirdi: aynalara yeni boyutta snapshot (karar 143 ek).
    func emitMirrorSnapshot(_ id: TerminalID, data: Data, cols: Int, rows: Int) {
        mirrorBroadcaster(for: id).send(.snapshot(data: data, cols: cols, rows: rows))
    }

    func subscribeScreenMirror(_ id: TerminalID) -> AsyncStream<TerminalMirrorEvent> {
        let state = serializeScreenState(id)
        let output = outputBroadcaster(for: id).stream()
        let resyncs = mirrorBroadcaster(for: id).stream()
        return AsyncStream { continuation in
            continuation.yield(.snapshot(data: state.data, cols: state.cols, rows: state.rows))
            let forwardOutput = Task { for await batch in output { continuation.yield(.output(batch)) } }
            let forwardResyncs = Task { for await event in resyncs { continuation.yield(event) } }
            continuation.onTermination = { _ in
                forwardOutput.cancel()
                forwardResyncs.cancel()
            }
        }
    }

    private var mirrorBroadcasters: [TerminalID: EventBroadcaster<TerminalMirrorEvent>] = [:]

    private func mirrorBroadcaster(for id: TerminalID) -> EventBroadcaster<TerminalMirrorEvent> {
        if let existing = mirrorBroadcasters[id] { return existing }
        let fresh = EventBroadcaster<TerminalMirrorEvent>()
        mirrorBroadcasters[id] = fresh
        return fresh
    }

    private func outputBroadcaster(for id: TerminalID) -> EventBroadcaster<Data> {
        if let existing = outputBroadcasters[id] { return existing }
        let fresh = EventBroadcaster<Data>()
        outputBroadcasters[id] = fresh
        return fresh
    }
}

// MARK: - Tests

@Suite @MainActor struct RemoteServiceTests {
    /// Deterministik UUID — sessionId = meta.id.description.
    private func makeSession(_ term: FakeTerminalServicing, uuid: UUID = UUID()) -> String {
        let meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo", createdAt: Date())
        term.metas.append(meta)
        return meta.id.description
    }

    @Test func subscribeSendsScrollbackThenData() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        term.scrollback = ("SCROLL".data(using: .utf8)!, 80, 24)
        let sid = makeSession(term)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(), connection: conn, chatSource: FakeChatTranscriptSource(events: []), config: FakeConfigService())
        await svc.start()

        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid])
        // scrollback gönderilene kadar bekle, sonra canlı çıktı üret
        try await conn.waitForSent(types: ["scrollback"])
        let tid = TerminalID(raw: UUID(uuidString: sid)!)
        term.emitOutput(tid, "LIVE".data(using: .utf8)!)
        try await conn.waitForSent(types: ["scrollback", "data"])

        #expect(await conn.firstString(type: "scrollback", key: "data") == "U0NST0xM") // base64 "SCROLL"
        #expect(await conn.firstInt(type: "scrollback", key: "seq") == 0)
        #expect(await conn.firstString(type: "data", key: "data") == "TElWRQ==")       // base64 "LIVE"
        #expect(await conn.firstInt(type: "data", key: "seq") == 1)
        svc.stop()
    }

    /// Karar 105: `awaitingDecisionChanged` olayı `sessions`'ı yeniden yayınlar;
    /// ilgili terminalin meta'sında `awaitingDecision` güncel değeri taşır.
    @Test func awaitingDecisionChangeRebroadcastsSessions() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let sid = makeSession(term)
        let tid = TerminalID(raw: UUID(uuidString: sid)!)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(), connection: conn, chatSource: FakeChatTranscriptSource(events: []), config: FakeConfigService())
        await svc.start()

        term.emit(.awaitingDecisionChanged(tid, true))
        try await conn.waitForCount(type: "sessions", atLeast: 1)
        #expect(await conn.lastSessionAwaitingDecision(id: sid) == true)

        term.emit(.awaitingDecisionChanged(tid, false))
        try await conn.waitForCount(type: "sessions", atLeast: 2)
        #expect(await conn.lastSessionAwaitingDecision(id: sid) == false)
        svc.stop()
    }

    @Test func welcomeSendsSessionsAndRepos() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let repoSvc = FakeRepoService()
        await repoSvc.setRepos([
            Repo(name: "lumi", path: "/a/lumi", isGitRepo: true, source: .standalone),
            Repo(name: "beta", path: "/a/beta", isGitRepo: false, source: .standalone),
        ])
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: repoSvc, connection: conn, chatSource: FakeChatTranscriptSource(events: []), config: FakeConfigService())
        await svc.start()

        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["sessions", "repos"])

        #expect(await conn.repoNames() == ["lumi", "beta"])
        svc.stop()
    }

    @Test func inputWritesToTerminal() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let sid = makeSession(term)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(), connection: conn, chatSource: FakeChatTranscriptSource(events: []), config: FakeConfigService())
        await svc.start()

        await conn.injectInbound(type: "input", payload: ["sessionId": sid, "data": "aGk="]) // "hi"
        try await term.waitForInput()

        let tid = TerminalID(raw: UUID(uuidString: sid)!)
        #expect(term.writtenInput[tid] == "hi".data(using: .utf8))
        svc.stop()
    }

    /// start_session, spawn'dan ÖNCE çalışma alanını güvenli işaretlemeli —
    /// remote claude ilk-açılış güven menüsünde takılıp transcript yazmayı
    /// bırakmasın (chat "yükleniyor"da kalmasın).
    @Test func startSessionMarksWorkspaceTrusted() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let trust = FakeClaudeWorkspaceTrust()
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
                                connection: conn, chatSource: FakeChatTranscriptSource(events: []),
                                trust: trust, config: FakeConfigService())
        await svc.start()

        await conn.injectInbound(type: "command", payload: [
            "action": "start_session", "repoPath": "/repo/untrusted",
            "prompt": "merhaba", "commandId": "c1"])
        try await conn.waitForSent(types: ["command_result"])

        #expect(trust.trusted == ["/repo/untrusted"])
        #expect(term.metas.map(\.repoPath) == ["/repo/untrusted"]) // spawn da oldu
        svc.stop()
    }

    @Test func exitedEventCancelsPerSessionDataTask() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        term.scrollback = ("X".data(using: .utf8)!, 80, 24)
        let sid = makeSession(term)
        let tid = TerminalID(raw: UUID(uuidString: sid)!)
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(), connection: conn, chatSource: FakeChatTranscriptSource(events: []), config: FakeConfigService())
        await svc.start()

        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid])
        try await conn.waitForSent(types: ["scrollback"])
        term.emitOutput(tid, "A".data(using: .utf8)!)
        try await conn.waitForSent(types: ["data"])
        let dataCountBefore = await conn.count(type: "data")

        // Terminal exit → per-session data task iptal edilmeli
        term.emit(.exited(tid, code: 0))
        // İptalin işlenmesi için kısa bekleme; sonra daha fazla çıktı üret
        try await Task.sleep(for: .milliseconds(50))
        #expect(svc.hasActiveSubscription(tid) == false)
        term.emitOutput(tid, "B".data(using: .utf8)!)

        // Exit sonrası yeni 'data' gelmemeli
        try await conn.waitForNoSent(type: "data", after: dataCountBefore, for: .milliseconds(100))
        svc.stop()
    }

    /// Faz 2 söküm / Karar 79: mode=chat + terminal UUID, provider=nil (bash) →
    /// chat oturumu yok → boş chat + idle; feed KURULMAZ.
    /// Claude provider terminaller için transcript köprüsü kur (bkz. RemoteServiceClaudeChatTests).
    @Test func subscribeChatModeForTerminalUUIDEmitsEmptyChatAndIdle() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let uuid = UUID()
        let meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        term.metas.append(meta)
        let sid = meta.id.description
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
                                connection: conn, chatSource: FakeChatTranscriptSource(events: []),
                                config: FakeConfigService())
        await svc.start()

        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForSent(types: ["chat", "chat_status"])
        // Scrollback artık chat modu için kurulmaz (söküm)
        try await conn.waitForNoSent(type: "scrollback", after: 0, for: .milliseconds(150))
        svc.stop()
    }

    /// Faz 2 söküm: terminal UUID + mode=chat → chatSubscription artık KULLANILMIYOR
    /// (chatBridgeTasks string-keyli). Terminal modu exit → feed task iptal edilir.
    @Test func exitedEventCancelsFeedTaskForTerminalMode() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let uuid = UUID()
        let meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        term.metas.append(meta)
        let sid = meta.id.description
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
                                connection: conn, chatSource: FakeChatTranscriptSource(events: []),
                                config: FakeConfigService())
        await svc.start()
        // Terminal mode subscribe → feed başlar
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid])
        try await conn.waitForSent(types: ["scrollback"])
        let tid = TerminalID(raw: uuid)
        #expect(svc.hasActiveSubscription(tid) == true)

        term.emit(.exited(tid, code: 0))
        try await Task.sleep(for: .milliseconds(50))
        #expect(svc.hasActiveSubscription(tid) == false)
        svc.stop()
    }

    /// Faz 2 söküm: mode=chat + terminal UUID (claudeSessionID yok) → boş chat + idle.
    /// Feed başlamaz (scrollback gelmez).
    @Test func chatModeForTerminalWithoutClaudeSessionSendsEmptyChat() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        term.scrollback = ("X".data(using: .utf8)!, 80, 24)
        let sid = makeSession(term)  // claudeSessionID yok
        let svc = RemoteService(paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
                                connection: conn, chatSource: FakeChatTranscriptSource(events: []),
                                config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        // Boş chat + idle (scrollback gelmez)
        try await conn.waitForSent(types: ["chat", "chat_status"])
        try await conn.waitForNoSent(type: "scrollback", after: 0, for: .milliseconds(150))
        svc.stop()
    }

    @Test @MainActor
    func listBranchesReturnsWorkspaceBranches() async throws {
        let term = FakeTerminalServicing()
        let repo = Repo(name: "R", path: "/tmp/r", isGitRepo: true, source: .projectsRoot)
        let repoSvc = FakeRepoService(repos: [repo])
        let ws = FakeWorkspaceService()
        await ws.setBranches(.success([WorkspaceBranch(name: "main"), WorkspaceBranch(name: "dev")]))
        let result = await RemoteCommandHandler(
            terminal: term, trust: NoopClaudeWorkspaceTrust(),
            chatSessions: NoopChatSessionService(), repos: repoSvc, workspaces: ws,
            config: FakeConfigService()
        ).handle(["action": "list_branches", "repoPath": "/tmp/r", "commandId": "c1"])

        #expect(result.ok)
        #expect(result.branches == ["main", "dev"])
        #expect(await ws.branchCalls.map(\.0) == ["/tmp/r"])
        #expect(await ws.branchCalls.map(\.1) == [100])
    }

    @Test @MainActor
    func listBranchesUnknownRepoFails() async throws {
        let repoSvc = FakeRepoService(repos: [])
        let ws = FakeWorkspaceService()
        let result = await RemoteCommandHandler(
            terminal: FakeTerminalServicing(), trust: NoopClaudeWorkspaceTrust(),
            chatSessions: NoopChatSessionService(), repos: repoSvc, workspaces: ws,
            config: FakeConfigService()
        ).handle(["action": "list_branches", "repoPath": "/nope", "commandId": "c1"])
        #expect(!result.ok)
        #expect(result.error == "unknown_repo")
    }

    // MARK: - start_session workspace/worktree dalı (Task 2)

    @Test @MainActor
    func startSessionNewBranchCreatesWorkspaceThenChat() async throws {
        let repo = Repo(name: "R", path: "/tmp/r", isGitRepo: true, source: .projectsRoot)
        let repoSvc = FakeRepoService(repos: [repo])
        let ws = FakeWorkspaceService()
        let wsPath = "/tmp/r-worktrees/feature-x"
        let created = ProjectWorkspace(projectPath: "/tmp/r", path: wsPath, name: "feature-x",
            branch: "feature-x", scm: .git)
        await ws.setCreateOutcome(.success(WorkspaceCreateResult(workspace: created, warning: nil)))
        let term = FakeTerminalServicing()
        let handler = RemoteCommandHandler(
            terminal: term, trust: NoopClaudeWorkspaceTrust(),
            chatSessions: FakeChatSessionService(), repos: repoSvc, workspaces: ws,
            config: FakeConfigService())

        let result = await handler.handle([
            "action": "start_session", "kind": "chat", "repoPath": "/tmp/r",
            "prompt": "selam", "branchMode": "new", "branchName": "feature-x", "commandId": "c1"])

        #expect(result.ok)
        let calls = await ws.createCalls
        #expect(calls.count == 1)
        #expect(calls.first?.request.branchMode == .new)
        #expect(calls.first?.request.branchName == "feature-x")
        // Karar 80: chat = worktree path'inde açılan claude terminali.
        #expect(term.metas.count == 1)
        #expect(term.metas.last?.repoPath == wsPath)
    }

    @Test @MainActor
    func startSessionCurrentModeSkipsWorkspaceCreate() async throws {
        let repo = Repo(name: "R", path: "/tmp/r", isGitRepo: true, source: .projectsRoot)
        let ws = FakeWorkspaceService()
        let term = FakeTerminalServicing()
        let handler = RemoteCommandHandler(
            terminal: term, trust: NoopClaudeWorkspaceTrust(),
            chatSessions: FakeChatSessionService(), repos: FakeRepoService(repos: [repo]), workspaces: ws,
            config: FakeConfigService())
        let result = await handler.handle([
            "action": "start_session", "kind": "chat", "repoPath": "/tmp/r",
            "prompt": "", "branchMode": "current", "commandId": "c1"])
        #expect(result.ok)
        #expect(await ws.createCalls.isEmpty)
        // Karar 80: current mod → mevcut repo path'inde claude terminali.
        #expect(term.metas.count == 1)
        #expect(term.metas.last?.repoPath == "/tmp/r")
    }

    @Test @MainActor
    func startSessionWorkspaceCreateFailureSurfacesError() async throws {
        let repo = Repo(name: "R", path: "/tmp/r", isGitRepo: true, source: .projectsRoot)
        let ws = FakeWorkspaceService()
        await ws.setCreateOutcome(.failure(WorkspaceFailure("kirli worktree")))
        let term = FakeTerminalServicing()
        let handler = RemoteCommandHandler(
            terminal: term, trust: NoopClaudeWorkspaceTrust(),
            chatSessions: FakeChatSessionService(), repos: FakeRepoService(repos: [repo]), workspaces: ws,
            config: FakeConfigService())
        let result = await handler.handle([
            "action": "start_session", "kind": "chat", "repoPath": "/tmp/r",
            "prompt": "", "branchMode": "existing", "branchName": "dev", "commandId": "c1"])
        #expect(!result.ok)
        // Karar 80: workspace create başarısız → terminal AÇILMAZ (chat da yok).
        #expect(term.metas.isEmpty)
    }
}
