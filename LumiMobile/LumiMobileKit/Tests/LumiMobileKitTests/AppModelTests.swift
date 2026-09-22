import XCTest
@testable import LumiMobileKit
import LumiWire

final class FakeRelayClient: RelayClienting, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [OutgoingCommand] = []
    private var _frames: [String] = []
    private var _started: [PairingInfo] = []
    private var _stopCount = 0
    var sendResult = true
    let stream: AsyncStream<ClientEvent>
    let continuation: AsyncStream<ClientEvent>.Continuation

    var commands: [OutgoingCommand] { lock.withLock { _commands } }
    var sentFrames: [String] { lock.withLock { _frames } }
    var started: [PairingInfo] { lock.withLock { _started } }
    var stopCount: Int { lock.withLock { _stopCount } }

    init() { (stream, continuation) = AsyncStream.makeStream() }

    /// Test helper: simulates a message arriving from the relay.
    func emit(_ message: ServerMessage) { continuation.yield(.message(message)) }

    func events() async -> AsyncStream<ClientEvent> { stream }
    func start(pairing: PairingInfo) async { lock.withLock { _started.append(pairing) } }
    func stop() async { lock.withLock { _stopCount += 1 } }
    @discardableResult func send(command: OutgoingCommand) async -> Bool {
        lock.withLock { () -> Bool in
            if sendResult { _commands.append(command) }
            return sendResult
        }
    }
    @discardableResult func send(frame: String) async -> Bool {
        lock.withLock { () -> Bool in
            if sendResult { _frames.append(frame) }
            return sendResult
        }
    }
    private var _pushRegistrations: [String] = []
    private var _pushUnregistrations: [String] = []
    var pushRegistrations: [String] { lock.withLock { _pushRegistrations } }
    var pushUnregistrations: [String] { lock.withLock { _pushUnregistrations } }
    func registerPush(deviceToken: String) async { lock.withLock { _pushRegistrations.append(deviceToken) } }
    func unregisterPush(deviceToken: String) async { lock.withLock { _pushUnregistrations.append(deviceToken) } }
    /// Test helper: clears sent frames (to reset the baseline in reconnect tests).
    func clearSentFrames() { lock.withLock { _frames.removeAll() } }
    /// Test helper: emits a ClientEvent (including stateChanged).
    func emit(_ event: ClientEvent) { continuation.yield(event) }
}

@MainActor
private func makeModel(paired: Bool = true) -> (AppModel, FakeRelayClient, InMemorySecureStore) {
    let client = FakeRelayClient()
    let store = InMemorySecureStore()
    if paired {
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
    }
    return (AppModel(client: client, store: store), client, store)
}

@MainActor
private func makeModelP(paired: Bool = true) -> (AppModel, FakeRelayClient, InMemoryPreferenceStore) {
    let client = FakeRelayClient()
    let store = InMemorySecureStore()
    let prefs = InMemoryPreferenceStore()
    if paired { store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef")) }
    return (AppModel(client: client, store: store, prefs: prefs), client, prefs)
}

private func meta(_ id: String, repo: String, _ status: String = "idle",
                  title: String? = nil, model: String? = nil,
                  cols: Int = 80, rows: Int = 24) -> SessionMeta {
    SessionMeta(id: id, repoName: repo, status: status, title: title, model: model, cols: cols, rows: rows)
}

private func data(_ id: String, seq: Int, _ text: String) -> TerminalChunk {
    TerminalChunk(sessionId: id, seq: seq, bytes: text.data(using: .utf8)!)
}

@MainActor
final class AppModelTests: XCTestCase {

    // MARK: Terminal byte-routing (Task 8)

    func testRoutesDataToSessionStream() async throws {
        let (model, client, _) = makeModel()
        await model.start()
        model.subscribe("s1")
        var got = Data()
        let stream = model.terminalStream("s1")
        client.emit(.data(data("s1", seq: 1, "hi")))
        for await chunk in stream { got.append(chunk.bytes); break }
        XCTAssertEqual(got, "hi".data(using: .utf8))
        XCTAssertTrue(client.sentFrames.contains { $0.contains(#""type":"subscribe""#) })
    }

    /// If scrollback arrives between subscribe and stream attach, the new stream replays it.
    func testTerminalStreamReplaysBufferedScrollback() async throws {
        let (model, _, _) = makeModel()
        model.subscribe("s1")
        // Scrollback arrived before the stream connected (view mounted late).
        model.handle(.scrollback(TerminalChunk(sessionId: "s1", seq: 0, cols: 80, rows: 24,
                                                bytes: "SCROLL".data(using: .utf8)!)))
        // Now the view connects to the stream → buffered scrollback should be replayed.
        var got = Data()
        let stream = model.terminalStream("s1")
        for await chunk in stream { got.append(chunk.bytes); break }
        XCTAssertEqual(got, "SCROLL".data(using: .utf8))
    }

    /// Terminal-mirror replay buffer stays at the cap (2048) when the view is not attached,
    /// and the NEWEST chunks are kept (head-drop). Long-session memory protection —
    /// locks the replayBufferCap behaviour added in Phase 1 (moved here when
    /// ChatLiveStripTests was removed; now exercised via terminal `subscribe`).
    func testTerminalReplayBufferIsCappedWhenViewUnattached() async {
        let (model, _, _) = makeModel()
        model.subscribe("s1")
        let cap = 2048
        for i in 0..<(cap + 10) {
            model.handle(.data(TerminalChunk(sessionId: "s1", seq: i, bytes: Data("\(i)".utf8))))
        }
        var got: [TerminalChunk] = []
        for await chunk in model.terminalStream("s1") {
            got.append(chunk)
            if got.count == cap { break }
        }
        XCTAssertEqual(got.count, cap)
        XCTAssertEqual(got.first?.seq, 10)       // oldest 10 were dropped
        XCTAssertEqual(got.last?.seq, cap + 9)   // newest were kept
    }

    /// subscribe/unsubscribe/sendInput send a frame asynchronously inside a Task; waits until it appears.
    private func awaitFrame(_ client: FakeRelayClient, containing needle: String) async {
        for _ in 0..<200 where !client.sentFrames.contains(where: { $0.contains(needle) }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testSubscribeSetsActiveAndSendsFrame() async {
        let (model, client, _) = makeModel()
        model.subscribe("s1")
        XCTAssertEqual(model.activeSessionId, "s1")
        await awaitFrame(client, containing: #""type":"subscribe""#)
        XCTAssertTrue(client.sentFrames.contains { $0.contains(#""type":"subscribe""#) && $0.contains(#""s1""#) })
    }

    func testUnsubscribeClearsActiveAndSendsFrame() async {
        let (model, client, _) = makeModel()
        model.subscribe("s1")
        model.unsubscribe("s1")
        XCTAssertNil(model.activeSessionId)
        await awaitFrame(client, containing: #""type":"unsubscribe""#)
        XCTAssertTrue(client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) })
    }

    func testSendInputSendsInputFrame() async {
        let (model, client, _) = makeModel()
        model.sendInput("s1", "hi".data(using: .utf8)!)
        await awaitFrame(client, containing: #""type":"input""#)
        let frame = client.sentFrames.first { $0.contains(#""type":"input""#) }
        XCTAssertNotNil(frame)
        XCTAssertTrue(frame!.contains("aGk="), "input base64 (\"hi\" == aGk=)")
    }

    /// Chat/command submission: text and Enter (CR) must be TWO separate input frames,
    /// NOT a combined `text\r`. A combined write is swallowed by the Claude Code TUI as
    /// an Enter before paste ingest completes and submit is not triggered (orca
    /// runtime-terminal-writer parity: text → settle → CR).
    func testSubmitTextSplitsTextAndEnterIntoSeparateFrames() async {
        let (model, client, _) = makeModel()
        model.submitSettle = .zero  // speed up the test (delay behaviour tested separately)
        model.submitText("s1", "hi")
        await awaitFrame(client, containing: "DQ==")  // CR frame'i (en son gelir)
        let inputs = client.sentFrames.filter { $0.contains(#""type":"input""#) }
        XCTAssertEqual(inputs.count, 2, "text and CR must be two separate input frames")
        XCTAssertTrue(inputs[0].contains("aGk="), #"first frame is text ("hi" == aGk=)"#)
        XCTAssertTrue(inputs[1].contains("DQ=="), #"second frame is CR (\r == DQ==)"#)
        XCTAssertFalse(inputs.contains { $0.contains("aGkN") },
                       #"combined "hi\r" (== aGkN) frame must NOT be present"#)
    }

    /// When subscribing to another session WITHOUT calling unsubscribe, the old stream should be finished.
    func testSubscribeSwitchFinishesPreviousStream() async {
        let (model, _, _) = makeModel()
        model.subscribe("s1")
        let s1Stream = model.terminalStream("s1")
        let drained = Task { () -> Int in
            var count = 0
            for await _ in s1Stream { count += 1 }
            return count  // returns when the s1 for-await ends
        }

        // Switch to s2 without unsubscribing → s1 sink should be finished
        model.subscribe("s2")

        // Late-arriving old s1 data must NOT be yielded to the s1 stream anymore.
        model.handle(.data(data("s1", seq: 9, "gec")))

        let count = await drained.value  // would hang here if not finished
        XCTAssertEqual(count, 0, "s1 stream should end without receiving any chunks")
        XCTAssertEqual(model.activeSessionId, "s2")
    }

    func testDataForInactiveSessionIsDropped() async {
        let (model, _, _) = makeModel()
        model.subscribe("s1")
        // s2 is not active → chunk is dropped (no buffer created)
        model.handle(.data(data("s2", seq: 1, "leak")))
        // When the s2 stream connects, nothing should be replayed — yield a live chunk and read it
        let stream = model.terminalStream("s2")
        model.handle(.data(data("s2", seq: 2, "live")))
        var got = Data()
        for await chunk in stream { got.append(chunk.bytes); break }
        XCTAssertEqual(got, "live".data(using: .utf8), "only live chunk should arrive, not the dropped 'leak'")
    }

    // MARK: Session list (welcome/sessions)

    func testWelcomeAppliesSessionsAndOfflineInfo() {
        let (model, _, _) = makeModel()
        model.handle(.welcome(Welcome(macOnline: false, lastSeenAt: 1_753_660_000_000,
                                      sessions: [meta("s1", repo: "lumi", "working")])))
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions.first?.repoName, "lumi")
        XCTAssertFalse(model.macOnline)
        XCTAssertEqual(model.lastSeenAt, Date(timeIntervalSince1970: 1_753_660_000))
    }

    func testSessionsMessageUpdatesListAndMarksMacOnline() {
        let (model, _, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "working"), meta("s2", repo: "beta", "idle")]))
        XCTAssertEqual(model.sessions.count, 2)
        XCTAssertTrue(model.macOnline, "sessions message comes from Mac → online")
    }

    // MARK: Repos (new session picker — bug #2)

    func testWelcomeAppliesRepos() {
        let (model, _, _) = makeModel()
        model.handle(.welcome(Welcome(macOnline: true, lastSeenAt: nil, sessions: [],
                                      repos: [Repo(name: "lumi", path: "/a/lumi"),
                                              Repo(name: "beta", path: "/a/beta")])))
        XCTAssertEqual(model.repos.map(\.name), ["lumi", "beta"])
        XCTAssertEqual(model.repos.map(\.path), ["/a/lumi", "/a/beta"])
    }

    func testReposMessageUpdatesListAndMarksMacOnline() {
        let (model, _, _) = makeModel()
        model.handle(.repos([Repo(name: "lumi", path: "/a/lumi")]))
        XCTAssertEqual(model.repos.count, 1)
        XCTAssertTrue(model.macOnline, "repos message comes from Mac → online")
    }

    func testReposDecodeFromWire() {
        let frame = #"{"v":1,"type":"repos","payload":{"repos":[{"name":"lumi","path":"/a/lumi"}]}}"#
        guard case .repos(let repos)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("repos frame could not be decoded")
        }
        XCTAssertEqual(repos, [Repo(name: "lumi", path: "/a/lumi")])
    }

    func testOrderedSessionsPutWaitingFirstThenErrorWorkingIdle() {
        let (model, _, _) = makeModel()
        model.handle(.sessions([
            meta("a", repo: "alpha", "idle"),
            meta("b", repo: "beta", "working"),
            meta("c", repo: "gamma", "waiting-unseen"),
            meta("d", repo: "delta", "error"),
            meta("e", repo: "epsilon", "waiting-seen"),
        ]))
        XCTAssertEqual(model.orderedSessions.map(\.repoName), ["epsilon", "gamma", "delta", "beta", "alpha"])
    }

    func testSessionsCloseClearsActiveSink() async {
        let (model, _, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "working")]))
        model.subscribe("s1")
        let stream = model.terminalStream("s1")
        // s1 closed: not in the new sessions list → sink finish → stream ends
        model.handle(.sessions([meta("s2", repo: "beta", "idle")]))
        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 0, "stream of a closed session should end")
    }

    // MARK: Model tracking (SessionMeta.model)

    func testSessionsAppliesModel() {
        let (model, _, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "working", model: "claude-sonnet-4-6")]))
        XCTAssertEqual(model.currentModel(for: "s1"), "claude-sonnet-4-6")
    }

    func testModelPersistsWhenLaterSessionsOmitsModel() {
        let (model, _, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "working", model: "claude-opus-4-8")]))
        model.handle(.sessions([meta("s1", repo: "lumi", "idle")]))  // no model field
        XCTAssertEqual(model.currentModel(for: "s1"), "claude-opus-4-8", "model is persisted information")
    }

    func testSetModelDispatchesCommand() async {
        let (model, client, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "working")]))
        await model.setModel(sessionId: "s1", model: "sonnet")
        XCTAssertEqual(client.commands.count, 1)
        guard case .setModel(let sid, let m) = client.commands[0].action else { return XCTFail() }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(m, "sonnet")
    }

    func testModelLabelPrettify() {
        let (model, _, _) = makeModel()
        XCTAssertEqual(model.modelLabel("claude-opus-4-8"), "Opus")
        XCTAssertEqual(model.modelLabel("claude-sonnet-4-6"), "Sonnet")
        XCTAssertEqual(model.modelLabel("claude-haiku-4-5"), "Haiku")
        XCTAssertEqual(model.modelLabel("weird-id"), "weird-id")
    }

    // MARK: Commands (start/delete + command_result)

    func testStartSessionLifecycle() async {
        let (model, client, _) = makeModel()
        XCTAssertEqual(model.startState, .idle)

        await model.startSession(repoPath: "/r/lumi", personaId: nil, prompt: "hello")
        XCTAssertEqual(model.startState, .sending)
        guard case .startSession(let repoPath, let personaId, let prompt, _, _, _, _, _) = client.commands[0].action else { return XCTFail() }
        XCTAssertEqual(repoPath, "/r/lumi")
        XCTAssertNil(personaId)
        XCTAssertEqual(prompt, "hello")

        model.handle(.commandResult(CommandResult(commandId: client.commands[0].commandId, ok: true, error: nil)))
        XCTAssertEqual(model.startState, .succeeded)

        model.resetStartState()
        XCTAssertEqual(model.startState, .idle)

        await model.startSession(repoPath: "/r/lumi", personaId: nil, prompt: "p")
        model.handle(.commandResult(CommandResult(commandId: client.commands[1].commandId, ok: false, error: "mac_offline")))
        XCTAssertEqual(model.startState, .failed("mac_offline"))
    }

    func testStartSessionFailureLandsInFailed() async {
        let (model, client, _) = makeModel()
        client.sendResult = false
        await model.startSession(repoPath: "/r/lumi", personaId: nil, prompt: "hello")
        XCTAssertEqual(model.startState, .failed("no connection"))
    }

    func testFailedCommandResultSurfacesErrorForSession() async {
        let (model, client, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "idle")]))
        await model.deleteSession(sessionId: "s1")
        let commandId = client.commands[0].commandId

        model.handle(.commandResult(CommandResult(commandId: commandId, ok: false, error: "terminal closed")))
        XCTAssertEqual(model.lastCommandError["s1"], "terminal closed")

        // next command clears the error
        await model.deleteSession(sessionId: "s1")
        XCTAssertNil(model.lastCommandError["s1"])

        // unknown commandId (another phone's command) is ignored
        model.handle(.commandResult(CommandResult(commandId: "other-phone-9", ok: false, error: "x")))
        XCTAssertNil(model.lastCommandError["s1"])
    }

    /// Delete succeeded → session is immediately removed from the phone list (Mac does not
    /// broadcast sessions when deleting a chat session; "can't delete" regression).
    func testDeleteSessionRemovesFromListOnSuccess() async {
        let (model, client, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "r", "idle")]))
        await model.deleteSession(sessionId: "s1")
        let cid = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: cid, ok: true, error: nil)))
        XCTAssertFalse(model.sessions.contains { $0.id == "s1" },
                       "session should be removed from the list on successful delete")
    }

    /// Ghost session (after a Mac restart): session_not_found also removes from the local list.
    func testDeleteSessionRemovesOnSessionNotFound() async {
        let (model, client, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "r", "idle")]))
        await model.deleteSession(sessionId: "s1")
        let cid = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: cid, ok: false, error: "session_not_found")))
        XCTAssertFalse(model.sessions.contains { $0.id == "s1" },
                       "ghost session (session_not_found) should also be removed from the list")
    }

    func testDeleteSessionDispatchesCommand() async {
        let (model, client, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "idle")]))
        await model.deleteSession(sessionId: "s1")
        XCTAssertEqual(client.commands.count, 1)
        guard case .deleteSession(let sid) = client.commands[0].action else { return XCTFail() }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(model.sessions.count, 1, "deleteSession does not optimistically remove locally — waits for sessions")
    }

    // MARK: Lifecycle / connection

    func testStartConsumesClientEventStream() async {
        let (model, client, _) = makeModel()
        await model.start()
        XCTAssertEqual(client.started.count, 1, "start starts the client when paired")

        client.continuation.yield(.stateChanged(.connected))
        client.continuation.yield(.message(.sessions([meta("s1", repo: "lumi", "idle")])))

        for _ in 0..<200 where !(model.sessions.count == 1 && model.connection == .connected) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.connection, .connected)
    }

    func testDisconnectedStateSetsMacOnlineFalse() async {
        let (model, client, _) = makeModel()
        await model.start()

        client.continuation.yield(.message(.welcome(Welcome(macOnline: true, lastSeenAt: nil))))
        for _ in 0..<200 where !model.macOnline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.macOnline, "mac should be online after welcome")

        client.continuation.yield(.stateChanged(.disconnected))
        for _ in 0..<200 where model.macOnline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.macOnline, "macOnline should be false after disconnected")
    }

    func testPairStartsClientAndUnpairStops() async {
        let (model, client, store) = makeModel(paired: false)
        XCTAssertFalse(model.isPaired)

        let bad = await model.pair(from: "gecersiz")
        XCTAssertFalse(bad)

        let ok = await model.pair(from: "lumi-remote://pair?url=wss%3A%2F%2Fr.example&token=0123456789abcdef")
        XCTAssertTrue(ok)
        XCTAssertTrue(model.isPaired)
        XCTAssertEqual(store.read()?.token, "0123456789abcdef")
        XCTAssertEqual(client.started.map(\.relayUrl), ["wss://r.example"])

        await model.unpair()
        XCTAssertFalse(model.isPaired)
        XCTAssertNil(store.read())
        XCTAssertGreaterThanOrEqual(client.stopCount, 1)
        XCTAssertTrue(model.lastCommandError.isEmpty)
        XCTAssertNil(model.activeSessionId)
        XCTAssertEqual(model.startState, .idle)
    }

    // MARK: Push state (Task 4 — preserved)

    func testApplyPushTokenRegistersWhenEnabled() async {
        let (model, client, prefs) = makeModelP()
        prefs.set(true, forKey: "notificationsEnabled")
        let model2 = AppModel(client: client, store: InMemorySecureStore(), prefs: prefs)
        XCTAssertTrue(model2.notificationsEnabled)
        await model2.applyPushToken("tok-1")
        XCTAssertEqual(client.pushRegistrations, ["tok-1"])
        _ = model
    }

    func testApplyPushTokenNoRegisterWhenDisabled() async {
        let (model, client, _) = makeModelP()
        XCTAssertFalse(model.notificationsEnabled)
        await model.applyPushToken("tok-1")
        XCTAssertTrue(client.pushRegistrations.isEmpty)
    }

    func testMarkEnabledTrueRegistersTokenAndPersists() async {
        let (model, client, prefs) = makeModelP()
        await model.applyPushToken("tok-1")
        await model.markNotificationsEnabled(true)
        XCTAssertTrue(model.notificationsEnabled)
        XCTAssertTrue(prefs.bool(forKey: "notificationsEnabled"))
        XCTAssertEqual(client.pushRegistrations, ["tok-1"])
    }

    func testMarkEnabledFalseUnregistersToken() async {
        let (model, client, prefs) = makeModelP()
        await model.applyPushToken("tok-1")
        await model.markNotificationsEnabled(true)
        await model.markNotificationsEnabled(false)
        XCTAssertFalse(model.notificationsEnabled)
        XCTAssertFalse(prefs.bool(forKey: "notificationsEnabled"))
        XCTAssertEqual(client.pushUnregistrations, ["tok-1"])
    }

    func testReRegisterAfterWelcomeWhenEnabled() async {
        let (model, client, _) = makeModelP()
        await model.applyPushToken("tok-1")
        await model.markNotificationsEnabled(true)
        await model.reRegisterPushIfNeeded()
        XCTAssertEqual(client.pushRegistrations, ["tok-1", "tok-1"])
    }

    // MARK: Reconnect subscription replay (Task 11)

    /// When the connection drops and is re-established, an automatic re-subscribe should be sent for the active session.
    func testResubscribesActiveSessionOnReconnect() async throws {
        let (model, client, _) = makeModel()
        await model.start()
        model.subscribe("s1")
        // Clear the subscribe frame — only watch for the frame sent after reconnect.
        await awaitFrame(client, containing: #""type":"subscribe""#)
        client.clearSentFrames()
        // Connection drops then is re-established.
        client.emit(.stateChanged(.disconnected))
        client.emit(.stateChanged(.connected))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(
            client.sentFrames.contains { $0.contains(#""type":"subscribe""#) && $0.contains("s1") },
            "a re-subscribe frame for s1 should be sent after reconnect"
        )
    }

    /// After a disconnect and reconnect in chat mode, should re-subscribe in CHAT mode
    /// not TERMINAL — otherwise chat silently falls back to terminal and messages
    /// stop reaching the phone (handoff #6).
    func testResubscribesInChatModeOnReconnectWhenChatActive() async throws {
        let (model, client, _) = makeModel()
        await model.start()
        model.subscribeChat("s1")
        await awaitFrame(client, containing: #""mode":"chat""#)
        client.clearSentFrames()
        client.emit(.stateChanged(.disconnected))
        client.emit(.stateChanged(.connected))
        try await Task.sleep(for: .milliseconds(50))
        let sub = client.sentFrames.first { $0.contains(#""type":"subscribe""#) && $0.contains("s1") }
        XCTAssertNotNil(sub, "a re-subscribe for s1 should be sent after reconnect")
        XCTAssertTrue(sub!.contains(#""mode":"chat""#),
                      "reconnect in chat mode should re-subscribe in chat mode, not fall back to terminal")
    }

    /// Reconnect in terminal mode should stay in terminal mode (must not leak into chat).
    func testResubscribesInTerminalModeOnReconnectWhenTerminalActive() async throws {
        let (model, client, _) = makeModel()
        await model.start()
        model.subscribe("s1")
        await awaitFrame(client, containing: #""type":"subscribe""#)
        client.clearSentFrames()
        client.emit(.stateChanged(.disconnected))
        client.emit(.stateChanged(.connected))
        try await Task.sleep(for: .milliseconds(50))
        let sub = client.sentFrames.first { $0.contains(#""type":"subscribe""#) && $0.contains("s1") }
        XCTAssertNotNil(sub)
        XCTAssertTrue(sub!.contains(#""mode":"terminal""#), "reconnect in terminal mode should stay terminal")
    }

    /// When there is no active session, connecting should not send a subscribe frame.
    func testNoResubscribeWhenNoActiveSessionOnConnect() async throws {
        let (model, client, _) = makeModel()
        await model.start()
        // No subscribe was ever called — activeSessionId is nil.
        client.emit(.stateChanged(.connected))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(
            client.sentFrames.contains { $0.contains(#""type":"subscribe""#) },
            "no subscribe frame should be sent on connected when there is no active session"
        )
    }

    // MARK: Chat state + append merge (Task 10)

    func testChatSnapshotThenAppendMerges() async {
        let (model, _, _) = makeModel()
        let m1 = ChatMessage(id: "m1", role: .user, blocks: [.text("hi", presentation: nil)], timestampMs: nil, turnId: nil)
        let m2 = ChatMessage(id: "m2", role: .assistant, blocks: [.text("yo", presentation: nil)], timestampMs: nil, turnId: nil)
        model.handle(.chat(sessionId: "s1", messages: [m1]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["m1"])
        model.handle(.chatAppend(sessionId: "s1", messages: [m2]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["m1", "m2"])
        // If the same id arrives again it is updated, not duplicated.
        let m2b = ChatMessage(id: "m2", role: .assistant, blocks: [.text("yo!", presentation: nil)], timestampMs: nil, turnId: nil)
        model.handle(.chatAppend(sessionId: "s1", messages: [m2b]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["m1", "m2"])
        XCTAssertEqual(model.chatMessages("s1").last?.blocks, [.text("yo!", presentation: nil)])
    }

    func testSubscribeChatSendsModeFrame() async {
        let (model, client, _) = makeModel()
        model.subscribeChat("s1")
        await awaitFrame(client, containing: "\"mode\":\"chat\"")
        XCTAssertTrue(client.sentFrames.contains { $0.contains("\"mode\":\"chat\"") })
    }

    // MARK: chat_send routing (Phase 2 Task 4)

    /// submitText in a chat-kind session → chat_send frame (NOT PTY input).
    func testSubmitTextSendsChatSendFrameForChatSession() async {
        let (model, client, _) = makeModel()
        // Mark as a chat session (kind = "chat")
        model.handle(.sessions([
            SessionMeta(id: "s1", repoName: "lumi", status: "working",
                        cols: 80, rows: 24, kind: "chat")
        ]))
        model.subscribeChat("s1")
        model.submitText("s1", "hello")
        // wait for chat_send frame
        await awaitFrame(client, containing: "\"type\":\"chat_send\"")
        let chatSend = client.sentFrames.first { $0.contains("\"type\":\"chat_send\"") }
        XCTAssertNotNil(chatSend, "submitText in a chat session should send a chat_send frame")
        XCTAssertTrue(chatSend!.contains("hello"), "chat_send should contain the text")
        // PTY input frame must NOT be sent
        XCTAssertFalse(client.sentFrames.contains { $0.contains("\"type\":\"input\"") },
                       "PTY input frame must NOT be sent in a chat session")
    }

    /// submitText in a terminal session should keep the existing PTY path (not chat_send).
    func testSubmitTextKeepsTerminalRouteForTerminalSession() async {
        let (model, client, _) = makeModel()
        // Terminal session (no kind)
        model.handle(.sessions([meta("s1", repo: "lumi", "working")]))
        model.subscribe("s1")
        model.submitSettle = .zero
        model.submitText("s1", "ls")
        await awaitFrame(client, containing: "\"type\":\"input\"")
        XCTAssertTrue(client.sentFrames.contains { $0.contains("\"type\":\"input\"") },
                      "input frame should be sent in a terminal session")
        XCTAssertFalse(client.sentFrames.contains { $0.contains("\"type\":\"chat_send\"") },
                       "chat_send frame must NOT be sent in a terminal session")
    }

    // MARK: chatStreamingText (Phase 2 Task 4)

    /// chat_status streamingText → chatStreamingText working+leading → visible.
    func testChatStreamingTextVisibleWhenWorkingAndLeading() {
        let (model, _, _) = makeModel()
        // There is an assistant message
        let m1 = ChatMessage(id: "m1", role: .assistant,
                             blocks: [.text("Hello", presentation: nil)],
                             timestampMs: nil, turnId: nil)
        model.handle(.chat(sessionId: "s1", messages: [m1]))
        // Streaming text exceeds the last assistant text → visible
        model.handle(.chatStatus(sessionId: "s1",
            status: ChatTurnStatus(working: true, startedAtMs: 10, tool: nil,
                                   streamingText: "Hello world")))
        XCTAssertEqual(model.chatStreamingText("s1"), "Hello world")
    }

    /// chat_status streamingText ≤ last assistant text → nil (transcript settled).
    func testChatStreamingTextNilWhenCaughtUp() {
        let (model, _, _) = makeModel()
        let m1 = ChatMessage(id: "m1", role: .assistant,
                             blocks: [.text("Hello world", presentation: nil)],
                             timestampMs: nil, turnId: nil)
        model.handle(.chat(sessionId: "s1", messages: [m1]))
        model.handle(.chatStatus(sessionId: "s1",
            status: ChatTurnStatus(working: true, startedAtMs: 10, tool: nil,
                                   streamingText: "Hello")))
        XCTAssertNil(model.chatStreamingText("s1"), "streaming text is shorter — transcript settled, returns nil")
    }

    /// working=false → streaming nil.
    func testChatStreamingTextNilWhenIdle() {
        let (model, _, _) = makeModel()
        model.handle(.chatStatus(sessionId: "s1",
            status: ChatTurnStatus(working: false, startedAtMs: nil, tool: nil,
                                   streamingText: "x")))
        XCTAssertNil(model.chatStreamingText("s1"), "idle → nil")
    }

    // MARK: startChatSession (Phase 2 Task 4)

    /// startChatSession sends the start_session command with kind=chat.
    func testStartChatSessionSendsKindChat() async {
        let (model, client, _) = makeModel()
        await model.startChatSession(repoPath: "/r/lumi")
        XCTAssertEqual(model.startState, .sending)
        XCTAssertEqual(client.commands.count, 1)
        guard case .startSession(let repoPath, _, _, _, _, _, _, _) = client.commands[0].action else {
            return XCTFail("startChatSession should send a startSession action")
        }
        XCTAssertEqual(repoPath, "/r/lumi")
        // kind=chat must be in the payload — check the commandFrame JSON output
        let frame = PhoneProtocol.commandFrame(client.commands[0])
        XCTAssertTrue(frame.contains("\"kind\":\"chat\""), "start_session payload must contain kind:chat")
    }

    /// startChatSession commandResult sessionId → subscribeChat is called automatically.
    /// Final review #1 regression: after starting a chat session, the SECOND message the user
    /// types must go as `chat_send` — WITHOUT manually injecting a `sessions` broadcast
    /// (local chatSessionIds routing). Otherwise the message would silently fall to the
    /// PTY input path ("second message dead" bug).
    func testSubmitTextRoutesChatSendAfterStartWithoutSessionsBroadcast() async {
        let (model, client, _) = makeModel()
        await model.startChatSession(repoPath: "/r/lumi")
        let commandId = client.commands[0].commandId
        model.handle(.commandResult(CommandResult(commandId: commandId, ok: true,
                                                   error: nil, sessionId: "chat-xyz")))
        // sessions frame NEVER arrived; should still route to chat_send.
        model.submitText("chat-xyz", "second message")
        await awaitFrame(client, containing: "\"type\":\"chat_send\"")
        let sent = client.sentFrames.first { $0.contains("\"type\":\"chat_send\"") }
        XCTAssertNotNil(sent, "submitText in a chat session should send chat_send (without sessions broadcast)")
        XCTAssertTrue(sent!.contains("second message"))
        // Must NOT fall through to PTY input:
        XCTAssertFalse(client.sentFrames.contains { $0.contains("\"type\":\"input\"") },
                       "input frame must not be sent in a chat session")
    }

    func testStartChatSessionSubscribesChatOnSuccess() async {
        let (model, client, _) = makeModel()
        await model.startChatSession(repoPath: "/r/lumi")
        let commandId = client.commands[0].commandId
        // Mac returns ok with the sessionId
        model.handle(.commandResult(CommandResult(commandId: commandId, ok: true,
                                                   error: nil, sessionId: "new-session-42")))
        XCTAssertEqual(model.startState, .succeeded)
        // subscribeChat frame should be sent
        await awaitFrame(client, containing: "\"mode\":\"chat\"")
        let sub = client.sentFrames.first {
            $0.contains("\"type\":\"subscribe\"") && $0.contains("\"mode\":\"chat\"")
        }
        XCTAssertNotNil(sub, "a chat subscribe should be sent after startChatSession succeeds")
        XCTAssertTrue(sub!.contains("new-session-42"), "subscribe should be for new-session-42")
    }

    // MARK: isChatSession view routing (Phase 2.1)

    /// REGRESSION: a terminal session (no kind) must NOT be counted as a chat session.
    /// Previously TerminalSessionView was opening every session in chat mode and leaving
    /// terminal sessions stuck on "loading" in a dead chat. isChatSession=false → mirror view.
    func testIsChatSessionFalseForTerminalSession() {
        let (model, _, _) = makeModel()
        model.handle(.sessions([meta("s1", repo: "lumi", "working")]))
        XCTAssertFalse(model.isChatSession("s1"),
                       "terminal session (no kind) must not be counted as chat → mirror view")
    }

    /// Chat session started by the phone → isChatSession true (local chatSessionIds;
    /// WITHOUT manually injecting a sessions broadcast → routes to chat view).
    func testIsChatSessionTrueAfterPhoneStartedChat() async {
        let (model, client, _) = makeModel()
        await model.startChatSession(repoPath: "/r/lumi")
        let commandId = client.commands[0].commandId
        model.handle(.commandResult(CommandResult(commandId: commandId, ok: true,
                                                   error: nil, sessionId: "chat-xyz")))
        XCTAssertTrue(model.isChatSession("chat-xyz"),
                      "a chat session started by the phone should have isChatSession=true")
    }

    /// A chat session started externally and broadcast with kind:chat → isChatSession true.
    func testIsChatSessionTrueForChatKindBroadcast() {
        let (model, _, _) = makeModel()
        model.handle(.sessions([
            SessionMeta(id: "s1", repoName: "lumi", status: "working",
                        cols: 80, rows: 24, kind: "chat")
        ]))
        XCTAssertTrue(model.isChatSession("s1"),
                      "a session broadcast with kind:chat should be counted as chat")
    }

    /// Unknown/non-existent session id → false (safe default: mirror).
    func testIsChatSessionFalseForUnknownSession() {
        let (model, _, _) = makeModel()
        XCTAssertFalse(model.isChatSession("nonexistent"))
    }

    // MARK: optimistic echo + streaming persistence (orca port; user complaint)

    private func hasText(_ messages: [ChatMessage], role: ChatRole, _ text: String) -> Bool {
        messages.contains { m in
            m.role == role && m.blocks.contains {
                if case .text(let t, _) = $0 { return t == text } else { return false }
            }
        }
    }

    /// The sent message appears in the render list IMMEDIATELY (without waiting for server acknowledgement).
    func testSubmitTextChatShowsOptimisticUserMessageImmediately() async {
        let (model, client, _) = makeModel()
        await model.startChatSession(repoPath: "/r")
        model.handle(.commandResult(CommandResult(commandId: client.commands[0].commandId,
                                                  ok: true, error: nil, sessionId: "cs1")))
        model.submitText("cs1", "hello")
        XCTAssertTrue(hasText(model.chatRenderMessages("cs1"), role: .user, "hello"),
                      "the sent message should appear immediately as an optimistic entry")
    }

    /// CRITICAL (no vanish): Mac's REAL broadcast order — chat_append (real message)
    /// first, chat_status(working=false) second. The bubble is hidden on append because the
    /// real message is in the list at that point; after the turn ends the text stays in the
    /// list (not deleted).
    func testStreamingReplacedByRealMessageNoVanish() {
        let (model, _, _) = makeModel()
        // Streaming starts.
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(
            working: true, startedAtMs: 1, tool: nil, streamingText: "Response")))
        XCTAssertTrue(model.chatRenderMessages("s1").contains { $0.id == "streaming" },
                      "streaming bubble should be visible during streaming")
        // Mac appends the real message first (status is still working=true).
        model.handle(.chatAppend(sessionId: "s1", messages: [ChatMessage(
            id: "a1", role: .assistant, blocks: [.text("Response complete", presentation: nil)],
            timestampMs: nil, turnId: nil)]))
        var render = model.chatRenderMessages("s1")
        XCTAssertTrue(render.contains { $0.id == "a1" }, "real message is in the list")
        XCTAssertFalse(render.contains { $0.id == "streaming" }, "bubble is hidden when real message arrives")
        // Then the turn ends.
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(
            working: false, startedAtMs: nil, tool: nil, streamingText: nil)))
        render = model.chatRenderMessages("s1")
        XCTAssertTrue(render.contains { $0.id == "a1" }, "message is still in the list after turn ends (no vanish)")
        XCTAssertFalse(render.contains { $0.id == "streaming" }, "no bubble after turn ends")
    }

    // MARK: Projects tree (Task 4)

    @MainActor
    func testProjectsMessagePopulatesTree() async {
        let (model, client, _) = makeModel()
        await model.start()
        client.emit(.message(.sessions([
            SessionMeta(id: "t1", repoName: "p", status: "waiting-unseen", cols: 80, rows: 24, provider: "claude"),
        ])))
        client.emit(.message(.projects(ProjectsSnapshot(projects: [
            ProjectNode(name: "p", path: "/p", checkouts: [
                CheckoutNode(kind: "original", title: "main", branch: nil, scm: "git",
                             path: "/p", agentIds: ["t1"])
            ])
        ], addable: [Repo(name: "orca", path: "/p/orca")]))))

        // Wait for async event loop to process
        for _ in 0..<200 where model.projectTree.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.projectTree.count, 1)
        XCTAssertEqual(model.projectTree[0].checkouts[0].agents.map(\.id), ["t1"])
        XCTAssertTrue(model.projectTree[0].checkouts[0].agents[0].needsAttention)
        XCTAssertEqual(model.projectsSnapshot.addable.map(\.path), ["/p/orca"])
        XCTAssertTrue(model.macOnline)
    }

    @MainActor
    func testAddProjectSendsCommand() async {
        let (model, client, _) = makeModel()
        await model.start()
        await model.addProject(path: "/p/orca")
        let sent = client.commands
        XCTAssertTrue(sent.contains { if case .addProject(let p) = $0.action { return p == "/p/orca" } else { return false } })
    }

    /// addProject failure sets addProjectError and is idempotent: second failure for same commandId is ignored.
    @MainActor
    func testAddProjectErrorOnFailedResult() async {
        let (model, client, _) = makeModel()
        await model.start()
        await model.addProject(path: "/p/x")
        let commandId = client.commands[0].commandId

        // Deliver a failing result
        model.handle(.commandResult(CommandResult(commandId: commandId, ok: false, error: "already_added")))
        XCTAssertEqual(model.addProjectError, "already_added")

        // Deliver a SECOND failing result for the same commandId (id was already removed, so this is a no-op)
        model.handle(.commandResult(CommandResult(commandId: commandId, ok: false, error: "again")))
        XCTAssertEqual(model.addProjectError, "already_added", "second result with same id should be ignored")
    }

    /// unpair() resets projectsSnapshot and addProjectError.
    @MainActor
    func testUnpairResetsProjectsState() async {
        let (model, client, _) = makeModel()
        await model.start()

        // Populate projectsSnapshot with a project
        client.emit(.message(.projects(ProjectsSnapshot(projects: [
            ProjectNode(name: "p", path: "/p", checkouts: [
                CheckoutNode(kind: "original", title: "main", branch: nil, scm: "git",
                             path: "/p", agentIds: [])
            ])
        ], addable: []))))

        // Wait for async processing
        for _ in 0..<200 where model.projectsSnapshot.projects.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }

        // Trigger a failed add_project to set addProjectError
        await model.addProject(path: "/p/x")
        let commandId = client.commands[0].commandId
        model.handle(.commandResult(CommandResult(commandId: commandId, ok: false, error: "already_added")))
        XCTAssertEqual(model.addProjectError, "already_added")

        // Unpair should reset both fields
        await model.unpair()
        XCTAssertTrue(model.projectsSnapshot.projects.isEmpty, "projects should be empty after unpair")
        XCTAssertNil(model.addProjectError, "addProjectError should be nil after unpair")
    }
}
