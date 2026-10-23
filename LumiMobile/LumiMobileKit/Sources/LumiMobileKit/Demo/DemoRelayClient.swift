import Foundation
import LumiWire

/// A fake relay + Mac for demo mode: the phone runs against realistic canned data
/// (projects with colors/emoji, loose terminals, rich Claude transcripts, a live
/// turn, a pending approval, an ANSI zsh screen) without a Mac or relay.
///
/// Speaks the same `ClientEvent` stream as `RelayClient`: `start` yields
/// `.connecting` → `.connected` → `welcome`; commands and raw frames from
/// `AppModel` are answered like the Mac would. Delays are injectable so tests
/// run instantly (`replyDelay: .zero`, `streamTick: nil`).
public actor DemoRelayClient: RelayClienting {
    private let replyDelay: Duration
    private let connectDelay: Duration
    private let streamTick: Duration?
    private let now: @Sendable () -> Date
    private var world: DemoWorld
    private var continuations: [UUID: AsyncStream<ClientEvent>.Continuation] = [:]
    private var isRunning = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var streamTask: Task<Void, Never>?
    private var terminalSeq: [String: Int] = [:]

    public static let defaultReplyDelay: Duration = .seconds(2)
    public static let defaultConnectDelay: Duration = .milliseconds(400)
    public static let defaultStreamTick: Duration = .milliseconds(350)
    private static let escapeByte: UInt8 = 0x1B
    private static let demoBranches = ["main", "develop", "feat/daily-rewards", "fix/tile-drop", "release/2.4"]

    /// - Parameters:
    ///   - replyDelay: time before a canned assistant reply lands after a phone message.
    ///   - connectDelay: time between `.connecting` and `.connected`.
    ///   - streamTick: word interval of the live streaming text on the working
    ///     session; nil disables the ticker.
    ///   - now: clock for `lastActivityAt` / timestamps.
    public init(replyDelay: Duration = defaultReplyDelay,
                connectDelay: Duration = defaultConnectDelay,
                streamTick: Duration? = defaultStreamTick,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.replyDelay = replyDelay
        self.connectDelay = connectDelay
        self.streamTick = streamTick
        self.now = now
        self.world = DemoWorld(nowMs: now().timeIntervalSince1970 * Self.msPerSecond)
    }

    private static let msPerSecond = 1000.0
    private var nowMs: Double { now().timeIntervalSince1970 * Self.msPerSecond }

    // MARK: RelayClienting

    public func events() -> AsyncStream<ClientEvent> {
        let (stream, continuation) = AsyncStream<ClientEvent>.makeStream()
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    public func start(pairing: PairingInfo) {
        guard !isRunning else { return }
        isRunning = true
        let delay = connectDelay
        spawn {
            await self.emit(.stateChanged(.connecting))
            try? await Task.sleep(for: delay)
            await self.connect()
        }
    }

    public func stop() {
        isRunning = false
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        streamTask?.cancel()
        streamTask = nil
        emit(.stateChanged(.disconnected))
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    @discardableResult
    public func send(command: OutgoingCommand) async -> Bool {
        guard isRunning else { return false }
        handle(command)
        return true
    }

    @discardableResult
    public func send(frame: String) async -> Bool {
        guard isRunning, let parsed = DemoFrame(frame) else { return false }
        handle(parsed)
        return true
    }

    public func registerPush(deviceToken: String) async {}
    public func unregisterPush(deviceToken: String) async {}

    // MARK: Connection

    private func connect() {
        guard isRunning else { return }
        emit(.stateChanged(.connected))
        emit(.message(.welcome(Welcome(
            macOnline: true, lastSeenAt: nowMs, sessions: world.sessions, repos: world.repos,
            projects: world.projects, addable: world.addable, others: world.others,
            looseLocations: world.looseLocations, display: DemoData.display))))
    }

    // MARK: Commands

    private func handle(_ command: OutgoingCommand) {
        let id = command.commandId
        switch command.action {
        case let .startSession(repoPath, _, prompt, _, branchMode, branchName, _, workspaceName):
            startSession(id, repoPath: repoPath, prompt: prompt, branchMode: branchMode,
                         branchName: branchName, workspaceName: workspaceName)
        case .deleteSession(let sessionId):
            let ok = world.deleteSession(sessionId)
            if ok { broadcastTree() }
            reply(id, ok: ok, error: ok ? nil : "session_not_found")
        case .addProject(let path):
            let ok = world.addProject(path: path)
            if ok { broadcastTree() }
            reply(id, ok: ok, error: ok ? nil : "not_addable")
        case .listBranches:
            reply(id, ok: true, branches: Self.demoBranches)
        case let .setModel(sessionId, model):
            world.update(sessionId, model: model, nowMs: nowMs)
            emit(.message(.sessions(world.sessions)))
            reply(id, ok: true)
        case let .sendText(sessionId, text):
            spawn { await self.runChatTurn(sessionId, text: text) }
            reply(id, ok: true)
        case .pressKey, .getHistory:
            reply(id, ok: true)
        }
    }

    private func startSession(_ commandId: String, repoPath: String, prompt: String,
                              branchMode: String?, branchName: String?, workspaceName: String?) {
        guard let sid = world.startSession(repoPath: repoPath, branchMode: branchMode, branchName: branchName,
                                           workspaceName: workspaceName, nowMs: nowMs) else {
            reply(commandId, ok: false, error: "invalid_path")
            return
        }
        // Tree first, so the new agent already exists when the phone navigates to it.
        broadcastTree()
        reply(commandId, ok: true, sessionId: sid)
        if !prompt.isEmpty { spawn { await self.runChatTurn(sid, text: prompt) } }
    }

    // MARK: Frames

    private func handle(_ frame: DemoFrame) {
        let sid = frame.string("sessionId") ?? ""
        switch frame.type {
        case "subscribe":
            frame.string("mode") == "chat" ? subscribeChat(sid) : subscribeTerminal(sid)
        case "unsubscribe":
            if sid == DemoIDs.tiles { stopStreaming() }
        case "input":
            if let bytes = frame.string("data").flatMap({ Data(base64Encoded: $0) }) { handleInput(sid, bytes) }
        case "chat_send":
            let text = frame.string("text") ?? ""
            spawn { await self.runChatTurn(sid, text: text) }
        case "prompt_respond":
            respondPrompt(sid, itemId: frame.string("itemId") ?? "", optionId: frame.string("optionId"))
        case "ping":
            emit(.message(.pong))
        default:
            break
        }
    }

    private func subscribeChat(_ sid: String) {
        emit(.message(.chat(sessionId: sid, messages: world.messages(sid))))
        emit(.message(.chatStatus(sessionId: sid, status: world.turn(sid))))
        for prompt in world.pendingPrompts(sid) { emit(.message(.prompt(sessionId: sid, prompt: prompt))) }
        if sid == DemoIDs.tiles, world.turn(sid).working { startStreaming(sid) }
    }

    private func subscribeTerminal(_ sid: String) {
        guard let meta = world.session(sid) else { return }
        terminalSeq[sid] = 0
        emit(.message(.scrollback(TerminalChunk(sessionId: sid, seq: 0, cols: meta.cols, rows: meta.rows,
                                                bytes: DemoTerminalScreens.scrollback(for: sid)))))
    }

    private func handleInput(_ sid: String, _ bytes: Data) {
        guard let meta = world.session(sid) else { return }
        if meta.kind == "chat" {
            if bytes == Data([Self.escapeByte]), world.turn(sid).working { interrupt(sid) }
            return
        }
        let seq = (terminalSeq[sid] ?? 0) + 1
        terminalSeq[sid] = seq
        emit(.message(.data(TerminalChunk(sessionId: sid, seq: seq, bytes: DemoTerminalScreens.echo(bytes)))))
    }

    // MARK: Chat turns

    private func runChatTurn(_ sid: String, text: String) async {
        guard world.session(sid) != nil else { return }
        let userMessages = world.appendChat(sid, nowMs: nowMs) { $0.user(text) }
        emit(.message(.chatAppend(sessionId: sid, messages: userMessages)))
        beginTurn(sid, tool: nil, streamingText: DemoReplies.streamingPreview(for: text))
        try? await Task.sleep(for: replyDelay)
        guard !Task.isCancelled, world.turn(sid).working else { return }
        let cwd = world.cwd(of: sid)
        let reply = world.appendChat(sid, nowMs: nowMs) { DemoReplies.reply(to: text, cwd: cwd, builder: &$0) }
        emit(.message(.chatAppend(sessionId: sid, messages: reply)))
        finishTurn(sid)
    }

    private func respondPrompt(_ sid: String, itemId: String, optionId: String?) {
        guard let resolved = world.resolvePrompt(sid, itemId: itemId, optionId: optionId) else { return }
        emit(.message(.prompt(sessionId: sid, prompt: resolved)))
        world.update(sid, awaitingDecision: false, nowMs: nowMs)
        beginTurn(sid, tool: "Bash", streamingText: nil)
        let allowed = optionId?.hasPrefix("allow") ?? true
        spawn { await self.completeApproval(sid, allowed: allowed) }
    }

    private func completeApproval(_ sid: String, allowed: Bool) async {
        try? await Task.sleep(for: replyDelay)
        guard !Task.isCancelled, world.session(sid) != nil else { return }
        let settled = world.completeRunningTools(sid)
        let outcome = world.appendChat(sid, nowMs: nowMs) { DemoReplies.approvalOutcome(allowed: allowed, builder: &$0) }
        emit(.message(.chatAppend(sessionId: sid, messages: settled + outcome)))
        finishTurn(sid)
    }

    private func beginTurn(_ sid: String, tool: String?, streamingText: String?) {
        let status = ChatTurnStatus(working: true, startedAtMs: Int(nowMs), tool: tool, streamingText: streamingText)
        world.setTurn(sid, status)
        world.update(sid, status: "working", nowMs: nowMs)
        emit(.message(.chatStatus(sessionId: sid, status: status)))
        emit(.message(.sessions(world.sessions)))
    }

    private func finishTurn(_ sid: String) {
        world.setTurn(sid, .idle)
        world.update(sid, status: "waiting-seen", nowMs: nowMs)
        emit(.message(.chatStatus(sessionId: sid, status: .idle)))
        emit(.message(.sessions(world.sessions)))
    }

    /// Esc on a working chat (decision 104 Stop): close the turn like Claude does.
    private func interrupt(_ sid: String) {
        if sid == DemoIDs.tiles { stopStreaming() }
        let note = world.appendChat(sid, nowMs: nowMs) { $0.say("_[Request interrupted by user]_") }
        emit(.message(.chatAppend(sessionId: sid, messages: note)))
        finishTurn(sid)
    }

    // MARK: Live streaming (tiles)

    private func startStreaming(_ sid: String) {
        guard let tick = streamTick, streamTask == nil else { return }
        let words = DemoData.tilesStreaming.split(separator: " ").map(String.init)
        streamTask = Task {
            for count in 1...words.count {
                try? await Task.sleep(for: tick)
                if Task.isCancelled { return }
                self.updateStreaming(sid, text: words.prefix(count).joined(separator: " "))
            }
        }
    }

    private func updateStreaming(_ sid: String, text: String) {
        var status = world.turn(sid)
        guard status.working else { return }
        status.streamingText = text
        world.setTurn(sid, status)
        emit(.message(.chatStatus(sessionId: sid, status: status)))
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: Plumbing

    private func broadcastTree() {
        emit(.message(.sessions(world.sessions)))
        emit(.message(.projects(world.snapshot)))
    }

    private func reply(_ commandId: String, ok: Bool, error: String? = nil,
                       sessionId: String? = nil, branches: [String]? = nil) {
        emit(.message(.commandResult(CommandResult(commandId: commandId, ok: ok, error: error,
                                                   sessionId: sessionId, branches: branches))))
    }

    private func emit(_ event: ClientEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    private func spawn(_ work: @escaping @Sendable () async -> Void) {
        let id = UUID()
        tasks[id] = Task {
            await work()
            self.taskFinished(id)
        }
    }

    private func taskFinished(_ id: UUID) { tasks[id] = nil }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
}

/// A parsed `{"v":1,"type":…,"payload":{…}}` envelope sent by the phone.
private struct DemoFrame {
    let type: String
    let payload: [String: Any]

    init?(_ text: String) {
        guard let data = text.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        self.type = type
        self.payload = dict["payload"] as? [String: Any] ?? [:]
    }

    func string(_ key: String) -> String? { payload[key] as? String }
}
