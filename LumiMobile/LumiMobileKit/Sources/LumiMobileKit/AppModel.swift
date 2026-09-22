import Foundation
import Observation
import LumiWire

public enum StartSessionState: Sendable, Equatable {
    case idle, sending, succeeded
    case failed(String)
}

/// Single view-model: reduces RelayClient events to UI state, sends commands.
/// client→model AsyncStream, model→UI @Observable (repo pattern; no Combine).
///
/// Terminal-mirror model: Mac sends raw PTY bytes via `data`/`scrollback` messages,
/// the model routes them to the subscribed session's `terminalStream` (consumed by the SwiftTerm view).
/// Keystrokes are sent back as `input` frames via `sendInput`.
@Observable @MainActor
public final class AppModel {
    public private(set) var isPaired: Bool
    public private(set) var connection: ConnectionState = .disconnected
    public private(set) var macOnline = false
    public private(set) var lastSeenAt: Date?
    /// List of active terminal sessions (from welcome/sessions message).
    public private(set) var sessions: [SessionMeta] = []
    /// Currently subscribed (displayed) session; used to re-subscribe on reconnect (Task 11).
    public private(set) var activeSessionId: String?
    /// Mode of the active subscription (chat or terminal). Kept to re-subscribe in the
    /// SAME mode on reconnect — otherwise, after a disconnect in chat mode it would fall
    /// back to terminal mode and `chat`/`chat_append` frames would stop arriving,
    /// causing messages not to reach the phone (handoff #6).
    private var activeChatMode = false
    public private(set) var repos: [Repo] = []
    public private(set) var personas: [Persona] = []
    public private(set) var lastCommandError: [String: String] = [:]
    public private(set) var startState: StartSessionState = .idle
    public private(set) var notificationsEnabled: Bool
    public private(set) var notificationAuthStatus: NotificationAuthStatus = .notDetermined
    public weak var pushControl: (any PushControlling)?

    private let client: any RelayClienting
    private let store: any SecureStore
    private let prefs: any PreferenceStore
    private var latestPushToken: String?
    private static let notificationsKey = "notificationsEnabled"
    private var consumeTask: Task<Void, Never>?
    private var commandCounter = 0
    /// sessionId → current model id (from SessionMeta.model; persisted information).
    private var models: [String: String] = [:]
    /// commandId → sessionId; "" for start_session (session doesn't exist yet).
    private var commandTargets: [String: String] = [:]
    /// delete_session command ids — used to clean up the local list on commandResult.
    private var deleteCommandIds: Set<String> = []
    /// Branch loading state (for the list_branches command).
    public private(set) var branchesForRepo: [String] = []
    public private(set) var branchesLoading = false
    public private(set) var branchesError: String?
    private var branchRequestIds: Set<String> = []
    /// Stream-json chat sessions started by this phone. `submitText` routing
    /// checks this — so chat messages never accidentally fall through to PTY input
    /// even if the `sessions` broadcast is delayed (final review #1: cannot depend on kind broadcast race).
    private var chatSessionIds: Set<String> = []

    // MARK: Projects state (Task 4)

    /// Latest projects tree snapshot (favorites mirror from the Mac).
    public private(set) var projectsSnapshot = ProjectsSnapshot(projects: [], addable: [])
    /// Last add_project failure (surfaced by the add sheet).
    public private(set) var addProjectError: String?
    private var addProjectCommandIds: Set<String> = []

    // MARK: Terminal byte-routing

    /// Live chunk consumer for the active session (SwiftTerm view). A single consumer is sufficient.
    private var terminalSinks: [String: AsyncStream<TerminalChunk>.Continuation] = [:]
    /// Replay buffer for chunks that arrive before the view connects to the stream.
    /// When the view calls `terminalStream`, these are replayed in order first, then the live stream follows.
    private var replayBuffers: [String: [TerminalChunk]] = [:]
    /// Prevents unbounded memory accumulation while the strip is unmounted (no sink).
    /// Oldest chunks are dropped; mid-stream replay may cause brief visual glitches,
    /// which are acceptable since the Claude TUI performs full repaints frequently.
    private static let replayBufferCap = 2048

    // MARK: Chat state (mode=chat; orca native-chat)

    /// sessionId → chat messages (mode=chat subscription; orca native-chat).
    private var chatBySession: [String: [ChatMessage]] = [:]
    /// Optimistic user message echoes (orca pending echo — client-side, immediate).
    /// Retired via count-based dedup when the transcript echoes them; kept otherwise.
    private var pendingBySession: [String: [ChatPending]] = [:]
    private var pendingCounter = 0
    /// Per-session streaming gate (port of orca deriveMobileNativeChatStreaming).
    private var streamingGates: [String: ChatStreamGate] = [:]
    /// Visible streaming text that passed through the gate (read by the view;
    /// hidden when the real message lands in the tail or the turn ends).
    public private(set) var gatedStreaming: [String: String] = [:]
    /// sessionId → latest live turn status (Phase 2; from chat_status frame).
    public private(set) var turnStatus: [String: ChatTurnStatus] = [:]
    /// Phase 3: active (pending) interactive prompts per session.
    public private(set) var prompts: [String: [ChatPrompt]] = [:]

    public init(client: any RelayClienting, store: any SecureStore, prefs: any PreferenceStore = UserDefaultsPreferenceStore()) {
        self.client = client
        self.store = store
        self.prefs = prefs
        self.isPaired = store.read() != nil
        self.notificationsEnabled = prefs.bool(forKey: Self.notificationsKey)
    }

    // MARK: Lifecycle

    public func start() async {
        guard consumeTask == nil, let pairing = store.read() else { return }
        let stream = await client.events()
        consumeTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .stateChanged(let state):
                    self.connection = state
                    if state == .disconnected { self.macOnline = false }
                    // Task 11: Reconnect subscription replay.
                    // When the connection is re-established and there is an active session,
                    // send a re-subscribe to the Mac; the Mac restarts fresh scrollback + live data stream.
                    // If activeSessionId is nil (first connection or no subscriber) nothing happens.
                    if state == .connected, let sid = self.activeSessionId {
                        let mode = self.activeChatMode ? "chat" : "terminal"
                        Task { await self.client.send(frame: PhoneProtocol.subscribeFrame(sessionId: sid, mode: mode)) }
                    }
                case .message(let message):
                    self.handle(message)
                    if case .welcome = message { await self.reRegisterPushIfNeeded() }
                }
            }
        }
        await client.start(pairing: pairing)
    }

    @discardableResult
    public func pair(from string: String) async -> Bool {
        guard let info = Pairing.parse(string) else {
            DiagLog.shared.log("model", "pair parse failed")
            return false
        }
        DiagLog.shared.log("model", "pair ok relay=\(info.relayUrl)")
        store.write(info)
        isPaired = true
        await client.stop()
        consumeTask?.cancel()
        consumeTask = nil
        await start()
        await pushControl?.onPairingSucceeded()
        return true
    }

    public func unpair() async {
        store.clear()
        isPaired = false
        consumeTask?.cancel()
        consumeTask = nil
        await client.stop()
        connection = .disconnected
        macOnline = false
        sessions = []
        activeSessionId = nil
        for continuation in terminalSinks.values { continuation.finish() }
        terminalSinks = [:]
        replayBuffers = [:]
        chatBySession = [:]
        pendingBySession = [:]
        streamingGates = [:]
        gatedStreaming = [:]
        turnStatus = [:]
        prompts = [:]
        models = [:]
        lastCommandError = [:]
        commandTargets = [:]
        deleteCommandIds = []
        branchRequestIds = []
        branchesForRepo = []
        branchesLoading = false
        branchesError = nil
        startState = .idle
        projectsSnapshot = ProjectsSnapshot(projects: [], addable: [])
        addProjectError = nil
        addProjectCommandIds = []
    }

    // MARK: Incoming messages

    public func handle(_ message: ServerMessage) {
        if case .pong = message {} else {
            DiagLog.shared.log("model", "in \(Self.describe(message))")
        }
        switch message {
        case .welcome(let welcome):
            macOnline = welcome.macOnline
            lastSeenAt = welcome.lastSeenAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            if let metas = welcome.sessions { applySessions(metas) }
            if let repos = welcome.repos { self.repos = repos }
            if let projects = welcome.projects {
                projectsSnapshot = ProjectsSnapshot(projects: projects, addable: welcome.addable ?? [])
            }

        case .sessions(let metas):
            // Only the Mac can send a sessions message → Mac is online.
            macOnline = true
            applySessions(metas)

        case .repos(let repos):
            // Only the Mac can send a repos message → Mac is online.
            macOnline = true
            self.repos = repos

        case .scrollback(let chunk), .data(let chunk):
            macOnline = true
            route(chunk)

        case .commandResult(let result):
            if addProjectCommandIds.remove(result.commandId) != nil {
                if !result.ok { addProjectError = result.error ?? "couldn't add project" }
                return
            }
            if branchRequestIds.remove(result.commandId) != nil {
                branchesLoading = false
                if result.ok { branchesForRepo = result.branches ?? [] }
                else { branchesError = result.error ?? "couldn't load branches" }
                return
            }
            let wasDelete = deleteCommandIds.remove(result.commandId) != nil
            guard let target = commandTargets.removeValue(forKey: result.commandId) else { return }
            if target.isEmpty {
                startState = result.ok ? .succeeded : .failed(result.error ?? "couldn't open session")
                // start_session kind=chat → Mac returns sessionId → mark as a chat session
                // (for routing) + automatically subscribe to chat.
                if result.ok, let sid = result.sessionId {
                    chatSessionIds.insert(sid)
                    subscribeChat(sid)
                }
            } else if wasDelete {
                // Delete: when the Mac deletes a chat session it doesn't broadcast an updated `sessions` →
                // the phone list was stuck ("can't delete"). On success OR ghost session
                // (session_not_found, after a Mac restart) immediately clean up locally.
                if result.ok || result.error == "session_not_found" {
                    removeSessionLocally(target)
                } else {
                    lastCommandError[target] = result.error ?? "couldn't delete session"
                }
            } else if !result.ok {
                lastCommandError[target] = result.error ?? "command failed to send"
            }

        case .pong:
            break

        case .chat(let sessionId, let messages):
            macOnline = true
            chatBySession[sessionId] = messages
            pendingBySession[sessionId] = chatRetireLandedPending(
                messages: messages, current: pendingBySession[sessionId] ?? [])
            recomputeStreaming(sessionId)

        case .chatAppend(let sessionId, let messages):
            macOnline = true
            var current = chatBySession[sessionId] ?? []
            for message in messages {
                if let idx = current.firstIndex(where: { $0.id == message.id }) {
                    current[idx] = message
                } else {
                    current.append(message)
                }
            }
            chatBySession[sessionId] = current
            pendingBySession[sessionId] = chatRetireLandedPending(
                messages: current, current: pendingBySession[sessionId] ?? [])
            recomputeStreaming(sessionId)

        case .chatStatus(let sessionId, let status):
            macOnline = true
            turnStatus[sessionId] = status
            recomputeStreaming(sessionId)

        case .prompt(let sessionId, let p):
            macOnline = true
            var list = prompts[sessionId] ?? []
            list.removeAll { $0.itemId == p.itemId }
            if p.state == .pending { list.append(p) }   // resolved/cancelled → listede tutma
            prompts[sessionId] = list

        case .projects(let snap):
            macOnline = true
            projectsSnapshot = snap
        }
    }

    /// One-line diagnostic summary of an incoming message (message content is not logged).
    private static func describe(_ message: ServerMessage) -> String {
        switch message {
        case .welcome(let welcome):
            "welcome macOnline=\(welcome.macOnline) sessions=\(welcome.sessions?.count ?? 0)"
        case .commandResult(let result):
            "commandResult \(result.commandId) ok=\(result.ok) err=\(result.error ?? "-")"
        case .pong:
            "pong"
        case .sessions(let list):
            "sessions count=\(list.count)"
        case .scrollback(let chunk):
            "scrollback \(chunk.sessionId.prefix(8)) seq=\(chunk.seq)"
        case .data(let chunk):
            "data \(chunk.sessionId.prefix(8)) seq=\(chunk.seq)"
        case .repos(let repos):
            "repos count=\(repos.count)"
        case .chat(_, let messages):
            "chat count=\(messages.count)"
        case .chatAppend(_, let messages):
            "chat_append count=\(messages.count)"
        case .chatStatus(let sessionId, _):
            "chat_status \(sessionId.prefix(8))"
        case .prompt(let sessionId, let p):
            "prompt \(sessionId.prefix(8)) \(p.kind.rawValue) \(p.state.rawValue)"
        case .projects(let snap):
            "projects projects=\(snap.projects.count) addable=\(snap.addable.count)"
        }
    }

    /// Applies a SessionMeta list: persists model information, cleans up terminal
    /// resources for dead sessions.
    private func applySessions(_ metas: [SessionMeta]) {
        sessions = metas
        let liveIds = Set(metas.map(\.id))
        for meta in metas {
            if let m = meta.model { models[meta.id] = m }
        }
        models = models.filter { liveIds.contains($0.key) }
        lastCommandError = lastCommandError.filter { liveIds.contains($0.key) }
        // If the active session is no longer in the list (deleted/closed), close its sink.
        if let active = activeSessionId, !liveIds.contains(active) {
            terminalSinks[active]?.finish()
            terminalSinks[active] = nil
            replayBuffers[active] = nil
            chatBySession[active] = nil
            pendingBySession[active] = nil
            streamingGates[active] = nil
            gatedStreaming[active] = nil
            turnStatus[active] = nil
            prompts[active] = nil
        }
    }

    /// Routes an incoming chunk to the live sink of the relevant session; if the sink is
    /// not yet connected (view mounted late), accumulates in the replay buffer for the active session.
    private func route(_ chunk: TerminalChunk) {
        if let sink = terminalSinks[chunk.sessionId] {
            sink.yield(chunk)
        } else if chunk.sessionId == activeSessionId {
            var buf = replayBuffers[chunk.sessionId, default: []]
            buf.append(chunk)
            // Cap: prevent unbounded feed accumulation while the strip is unmounted (no sink) —
            // oldest chunk is dropped. Replay from mid-stream may cause brief visual glitches in the TUI;
            // acceptable since the Claude TUI performs full repaints frequently.
            if buf.count > Self.replayBufferCap { buf.removeFirst(buf.count - Self.replayBufferCap) }
            replayBuffers[chunk.sessionId] = buf
        }
        // Chunks for inactive/unsubscribed sessions are dropped (unwanted data).
    }

    // MARK: Terminal subscription API (consumed by Task 9/11)

    /// Marks the session as active and sends a `subscribe` frame. The Mac responds with
    /// scrollback + live data, which flow into `terminalStream(sessionId)`.
    public func subscribe(_ sessionId: String) {
        // If the session is changed without calling unsubscribe, clean up the previous
        // session's resources: otherwise the old view's `for await` never ends and late
        // arriving old `.data` is yielded to it.
        if let old = activeSessionId, old != sessionId {
            terminalSinks[old]?.finish()
            terminalSinks[old] = nil
            replayBuffers[old] = nil
        }
        activeSessionId = sessionId
        activeChatMode = false
        replayBuffers[sessionId] = []
        Task { await client.send(frame: PhoneProtocol.subscribeFrame(sessionId: sessionId)) }
    }

    /// Releases the subscription: clears state if it matches the active session,
    /// sends an `unsubscribe` frame, and terminates the live stream.
    public func unsubscribe(_ sessionId: String) {
        if activeSessionId == sessionId { activeSessionId = nil; activeChatMode = false }
        terminalSinks[sessionId]?.finish()
        terminalSinks[sessionId] = nil
        replayBuffers[sessionId] = nil
        Task { await client.send(frame: PhoneProtocol.unsubscribeFrame(sessionId: sessionId)) }
    }

    /// Sends a keystroke / byte sequence to the Mac PTY as an `input` frame.
    public func sendInput(_ sessionId: String, _ data: Data) {
        Task { await client.send(frame: PhoneProtocol.inputFrame(sessionId: sessionId, data: data)) }
    }

    /// Phase 3: interactive prompt response. No optimistic dismiss — the card is removed
    /// via `handle(.prompt)` when a resolution broadcast (state=resolved/cancelled) arrives.
    public func respondPrompt(_ sessionId: String, itemId: String, revision: Int, optionId: String) {
        Task { await client.send(frame: PhoneProtocol.promptRespondFrame(
            sessionId: sessionId, itemId: itemId, expectedRevision: revision, optionId: optionId)) }
    }

    /// Phase 3.1: question response (indices + free-text per question). No optimistic dismiss.
    public func respondPromptSelections(_ sessionId: String, itemId: String, revision: Int,
                                        selections: [(indices: [Int], other: String?)]) {
        Task { await client.send(frame: PhoneProtocol.promptRespondSelectionsFrame(
            sessionId: sessionId, itemId: itemId, expectedRevision: revision, selections: selections)) }
    }

    /// The "settle" window between the text and Enter in `submitText`.
    /// Default is orca parity (`AGENT_PROMPT_SUBMIT_SETTLE_MS` = 500 ms);
    /// tests can set it to zero to speed up.
    public var submitSettle: Duration = .milliseconds(500)

    /// Free-text submission (chat composer / terminal text bar):
    /// - Chat session (kind = "chat"): sends a `chat_send` frame (not PTY input).
    /// - Terminal session: sends the text as an `input` frame, waits `submitSettle`
    ///   for the agent to ingest the paste, then sends Enter (CR) as a SEPARATE
    ///   `input` frame.
    ///
    /// Why separate for the terminal path: a combined `text\r` in a single write is
    /// swallowed by the Claude Code TUI as an Enter before paste ingest completes,
    /// so submit is not triggered — the text appears on the input line but is not sent
    /// (orca `runtime-terminal-writer` parity: text → settle → CR). Keeping both writes
    /// in a SINGLE Task ensures ordering; separate `sendInput` calls do not guarantee
    /// Task order and Enter may overtake the text.
    public func submitText(_ sessionId: String, _ text: String) {
        // Chat session: chat_send frame (PTY bypass). Single source: isChatSession
        // (locally tracked chat id OR kind:chat in sessions broadcast).
        let isChat = isChatSession(sessionId)
        // Phase 2.1 diagnostics: which branch is running + that the frame entered the queue should
        // appear in the device log (evidence: "chat loading + message not going through" — 0 chat_send/input reached the Mac).
        DiagLog.shared.log("model", "submitText sid=\(sessionId.prefix(8)) chat=\(isChat) len=\(text.count)")
        if isChat {
            // Optimistic echo: the user's message lands in the list IMMEDIATELY (orca; client-side,
            // no server acknowledgement/latency wait). Retired via dedup if the transcript echoes it.
            appendChatPending(sessionId, text: text)
            Task {
                let ok = await client.send(frame: PhoneProtocol.chatSendFrame(sessionId: sessionId, text: text))
                DiagLog.shared.log("model", "out chat_send sid=\(sessionId.prefix(8)) ok=\(ok)")
            }
            return
        }
        // Terminal session: text → settle → CR (orca runtime-terminal-writer parity).
        Task {
            if !text.isEmpty {
                await client.send(frame: PhoneProtocol.inputFrame(sessionId: sessionId, data: Data(text.utf8)))
                try? await Task.sleep(for: submitSettle)
            }
            let ok = await client.send(frame: PhoneProtocol.inputFrame(sessionId: sessionId, data: Data([0x0D])))
            DiagLog.shared.log("model", "out input+CR sid=\(sessionId.prefix(8)) ok=\(ok)")
        }
    }

    /// Stream of scrollback + live data chunks arriving for the given session.
    /// On connection, the replay buffer accumulated since subscribe is delivered first in order,
    /// followed by live chunks. Only a single consumer at a time is supported;
    /// a new stream displaces the old one.
    public func terminalStream(_ sessionId: String) -> AsyncStream<TerminalChunk> {
        // Close the old consumer if any (the new stream becomes the sole owner).
        terminalSinks[sessionId]?.finish()
        let buffered = replayBuffers[sessionId] ?? []
        replayBuffers[sessionId] = []
        return AsyncStream { continuation in
            for chunk in buffered { continuation.yield(chunk) }
            terminalSinks[sessionId] = continuation
            // Consumer-side cancellation (view cancellation) should clean up the sink itself.
            // Single-consumer assumption holds → nil out the sink for that id.
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.terminalSinks[sessionId] = nil
                }
            }
        }
    }

    // MARK: Chat subscription API (Task 10)

    /// mode=chat subscription: set activeSessionId + send chat frame.
    public func subscribeChat(_ sessionId: String) {
        // Same cleanup as terminal subscription: if the old session's sink is not finished,
        // late arriving old .data is yielded to it (see subscribe(_:)).
        if let old = activeSessionId, old != sessionId {
            terminalSinks[old]?.finish()
            terminalSinks[old] = nil
            replayBuffers[old] = nil
        }
        activeSessionId = sessionId
        activeChatMode = true
        chatBySession[sessionId] = chatBySession[sessionId] ?? []
        // Don't drop scrollback that arrives before the strip mounts (subscribe(_:) parity).
        replayBuffers[sessionId] = []
        Task { await client.send(frame: PhoneProtocol.subscribeFrame(sessionId: sessionId, mode: "chat")) }
    }

    public func chatMessages(_ sessionId: String) -> [ChatMessage] {
        chatBySession[sessionId] ?? []
    }

    /// Combined message list for the view to render: optimistic pending + journal messages
    /// + gated streaming bubble (orca buildTransientData). The caller folds into turns via `foldChatMessages`.
    public func chatRenderMessages(_ sessionId: String) -> [ChatMessage] {
        chatAssembleRenderMessages(
            messages: chatBySession[sessionId] ?? [],
            pending: pendingBySession[sessionId] ?? [],
            streaming: gatedStreaming[sessionId])
    }

    /// Appends an optimistic user echo (orca pending-echo append).
    private func appendChatPending(_ sessionId: String, text: String) {
        let messages = chatBySession[sessionId] ?? []
        let normalized = normalizeChatUserText(text)
        let baselineOccurrences = chatCountUserTextOccurrences(messages, normalized)
        let baselineTailId = messages.last?.id
        pendingCounter += 1
        pendingBySession[sessionId] = chatPendingAppend(
            current: pendingBySession[sessionId] ?? [],
            id: "pending-\(pendingCounter)", text: text,
            baselineOccurrences: baselineOccurrences,
            baselineTailMessageId: baselineTailId)
    }

    /// Advances the streaming gate by one tick and writes the result to `gatedStreaming`.
    /// Called on both chat_status and message changes (chat/chat_append) — both look at
    /// the current turnStatus + folded. No preview is given when the turn is not live
    /// (orca mobileNativeChatStreamPreview); hidden via catch-up when the real message lands.
    private func recomputeStreaming(_ sessionId: String) {
        let working = turnStatus[sessionId]?.working ?? false
        // Preview only while the turn is live; once done, nil → bubble hidden
        // (the real message is in the transcript at that point, so no gap).
        let preview = working ? (turnStatus[sessionId]?.streamingText) : nil
        let folded = foldChatMessages(chatBySession[sessionId] ?? []).map { $0.message }
        let (newGate, streaming) = chatDeriveStreaming(
            gate: streamingGates[sessionId] ?? ChatStreamGate(),
            folded: folded, incoming: preview, streamLive: working)
        streamingGates[sessionId] = newGate
        gatedStreaming[sessionId] = streaming
    }

    // MARK: Derived state

    /// View-ready tree: joins the snapshot's agent ids against live `sessions`.
    public var projectTree: [ProjectRowData] {
        assembleProjectTree(snapshot: projectsSnapshot, sessions: sessions, selectedId: activeSessionId)
    }

    /// `waiting` first (design §4.3), then error/working/idle; within a group sorted by repo name.
    public var orderedSessions: [SessionMeta] {
        func priority(_ badge: Badge) -> Int {
            switch badge {
            case .waiting: 0
            case .error: 1
            case .working: 2
            case .idle: 3
            }
        }
        return sessions.sorted { a, b in
            let pa = priority(a.badge), pb = priority(b.badge)
            if pa != pb { return pa < pb }
            return a.repoName.localizedCaseInsensitiveCompare(b.repoName) == .orderedAscending
        }
    }

    public func session(_ id: String) -> SessionMeta? {
        sessions.first { $0.id == id }
    }

    /// Fully removes a deleted session from the phone's state (because the Mac does not
    /// broadcast `sessions` when a chat session is deleted — list + chat/pending/streaming/terminal state).
    private func removeSessionLocally(_ id: String) {
        sessions.removeAll { $0.id == id }
        chatSessionIds.remove(id)
        terminalSinks[id]?.finish()
        terminalSinks[id] = nil
        replayBuffers[id] = nil
        chatBySession[id] = nil
        pendingBySession[id] = nil
        streamingGates[id] = nil
        gatedStreaming[id] = nil
        turnStatus[id] = nil
        prompts[id] = nil
        models[id] = nil
        lastCommandError[id] = nil
        if activeSessionId == id { activeSessionId = nil; activeChatMode = false }
    }

    /// Is the session a stream-json chat session? View routing (chat view vs
    /// terminal-mirror) and `submitText` routing use THIS as the single source of truth:
    /// chat sessions started by this phone (locally tracked `chatSessionIds`) OR kind:chat
    /// in a `sessions` broadcast — whichever arrives first (broadcast race).
    /// Terminal sessions (kind nil/"terminal") return false → mirror view
    /// (Phase 2.1: previously TerminalSessionView was opening every session in chat mode →
    /// terminal sessions got stuck on "loading" in a dead chat).
    public func isChatSession(_ id: String) -> Bool {
        chatSessionIds.contains(id) || sessions.first(where: { $0.id == id })?.kind == "chat"
    }

    // MARK: Commands

    public func startSession(repoPath: String, personaId: String?, prompt: String) async {
        startState = .sending
        await dispatch(target: "", action: .startSession(repoPath: repoPath, personaId: personaId, prompt: prompt))
    }

    /// Phase 2: starts a pure chat session (kind=chat). The Mac returns the sessionId
    /// in commandResult; the `commandResult` handler automatically calls `subscribeChat`.
    public func startChatSession(repoPath: String, branchMode: String? = nil,
                                 branchName: String? = nil, baseBranch: String? = nil,
                                 workspaceName: String? = nil) async {
        startState = .sending
        await dispatch(target: "", action: .startSession(
            repoPath: repoPath, personaId: nil, prompt: "", kind: "chat",
            branchMode: branchMode, branchName: branchName,
            baseBranch: baseBranch, workspaceName: workspaceName))
    }

    /// Loads the branch list (list_branches command). The response is processed into branchesForRepo via commandResult.
    public func loadBranches(repoPath: String) async {
        branchesForRepo = []
        branchesError = nil
        branchesLoading = true
        commandCounter += 1
        let commandId = "ph-\(commandCounter)"
        branchRequestIds.insert(commandId)
        let ok = await client.send(command: OutgoingCommand(commandId: commandId, action: .listBranches(repoPath: repoPath)))
        if !ok {
            branchRequestIds.remove(commandId)
            branchesLoading = false
            branchesError = "no connection"
        }
    }

    public func resetStartState() {
        startState = .idle
    }

    // MARK: Streaming text (Phase 2 Task 4)

    /// Returns the live streaming text for the given session (orca gate parity).
    /// nil if not working or if the streaming text does not exceed the last assistant text —
    /// overlay drops when the transcript settles (spec Phase 2 §E).
    public func chatStreamingText(_ sessionId: String) -> String? {
        let status = turnStatus[sessionId] ?? .idle
        let lastAssistant = chatMessages(sessionId).last(where: { $0.role == .assistant })
        let lastText: String
        if let msg = lastAssistant {
            lastText = msg.blocks.compactMap {
                if case .text(let t, _) = $0 { return t } else { return nil }
            }.joined()
        } else {
            lastText = ""
        }
        return LumiMobileKit.chatStreamingText(working: status.working,
                                               streaming: status.streamingText,
                                               lastAssistantText: lastText)
    }

    public func deleteSession(sessionId: String) async {
        await dispatch(target: sessionId, action: .deleteSession(sessionId: sessionId))
    }

    /// Adds a Mac-known project to favorites (the one phone-side write). Not
    /// optimistic — the Mac appends the favorite and rebroadcasts `projects`.
    public func addProject(path: String) async {
        commandCounter += 1
        let commandId = "ph-\(commandCounter)"
        addProjectCommandIds.insert(commandId)
        addProjectError = nil
        let ok = await client.send(command: OutgoingCommand(commandId: commandId, action: .addProject(path: path)))
        DiagLog.shared.log("model", "out \(commandId) add_project ok=\(ok)")
        if !ok { addProjectCommandIds.remove(commandId); addProjectError = "no connection" }
    }

    public func currentModel(for sessionId: String) -> String? {
        models[sessionId]
    }

    public func setModel(sessionId: String, model: String) async {
        await dispatch(target: sessionId, action: .setModel(sessionId: sessionId, model: model))
    }

    /// Reduces a raw model id to a short label (UI).
    public func modelLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return raw
    }

    public func registerPush(deviceToken: String) async {
        await client.registerPush(deviceToken: deviceToken)
    }

    public func applyPushToken(_ hex: String) async {
        DiagLog.shared.log(
            "push", "token received \(hex.prefix(8))… enabled=\(notificationsEnabled)")
        latestPushToken = hex
        if notificationsEnabled { await client.registerPush(deviceToken: hex) }
    }

    public func setNotificationAuthStatus(_ status: NotificationAuthStatus) {
        notificationAuthStatus = status
    }

    public func markNotificationsEnabled(_ on: Bool) async {
        notificationsEnabled = on
        prefs.set(on, forKey: Self.notificationsKey)
        guard let token = latestPushToken else { return }
        if on { await client.registerPush(deviceToken: token) }
        else { await client.unregisterPush(deviceToken: token) }
    }

    public func enableNotifications() async -> EnableResult {
        await pushControl?.enable() ?? .declined
    }

    public func disableNotifications() async {
        await pushControl?.disable()
    }

    public func reRegisterPushIfNeeded() async {
        guard notificationsEnabled, let token = latestPushToken else { return }
        await client.registerPush(deviceToken: token)
    }

    // MARK: Helpers

    private func dispatch(target: String, action: CommandAction) async {
        commandCounter += 1
        let commandId = "ph-\(commandCounter)"
        commandTargets[commandId] = target
        if case .deleteSession = action { deleteCommandIds.insert(commandId) }
        if !target.isEmpty {
            lastCommandError[target] = nil
        }
        let ok = await client.send(command: OutgoingCommand(commandId: commandId, action: action))
        // Only the case name is logged via Mirror — message content does not appear in the log.
        let label = Mirror(reflecting: action).children.first?.label
            ?? String(describing: action)
        DiagLog.shared.log(
            "model", "out \(commandId) \(label) target=\(target.prefix(8)) ok=\(ok)")
        if !ok {
            commandTargets[commandId] = nil
            if target.isEmpty {
                startState = .failed("no connection")
            } else {
                lastCommandError[target] = "no connection"
            }
        }
    }
}
