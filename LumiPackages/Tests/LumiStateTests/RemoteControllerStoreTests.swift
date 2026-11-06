import Testing
import Foundation
@testable import LumiState
import LumiKit

// Remote route'unun seçim mantığı (docs/design/08, Faz 3).

@MainActor
private final class FakeController: RemoteControllerServicing {
    var directoryState: RemoteConnectionState = .disconnected
    var hubs: [RemoteHubInfo] = []
    var nextSessionId: String? = "new-session"
    var startError: Error?
    private let broadcaster = EventBroadcaster<RemoteControllerEvent>()

    func emit(_ event: RemoteControllerEvent) { broadcaster.send(event) }
    func linkState(_ hubId: String) -> RemoteHubLinkState { .connected }
    func snapshot(_ hubId: String) -> RemoteHubSnapshot? { nil }
    func configure(relayUrl: String, networkToken: String, identity: RemoteControllerIdentity) {}
    func stop() {}
    func connect(hubId: String, password: String?, remember: Bool) async {}
    func disconnect(hubId: String) {}
    func hasRememberedPassword(hubId: String) async -> Bool { false }
    func terminalOutput(hubId: String, sessionId: String) -> AsyncStream<RemoteTerminalChunk> { AsyncStream { $0.finish() } }
    func sendInput(hubId: String, sessionId: String, data: Data) { inputs.append(data) }
    func sendText(hubId: String, sessionId: String, text: String, submit: Bool) async throws {}
    func readTerminal(hubId: String, sessionId: String) async throws -> RemoteTerminalReading { .screen("") }
    private(set) var startedAt: [(path: String, kind: RemoteSessionKind)] = []
    func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind, prompt: String) async throws -> String? {
        startedAt.append((checkoutPath, kind))
        if let startError { throw startError }
        return nextSessionId
    }
    func closeSession(hubId: String, sessionId: String) async throws {}
    func events() -> AsyncStream<RemoteControllerEvent> { broadcaster.stream() }

    // Chat (karar 143 ek)
    private(set) var chatSubscriptions: [String?] = []
    private(set) var chatSent: [String] = []
    private(set) var answers: [(itemId: String, revision: Int, answer: RemotePromptAnswer)] = []
    private(set) var inputs: [Data] = []
    private var chatContinuation: AsyncStream<RemoteChatEvent>.Continuation?

    func chatEvents(hubId: String, sessionId: String, afterId: String?) -> AsyncStream<RemoteChatEvent> {
        chatSubscriptions.append(afterId)
        let (stream, continuation) = AsyncStream.makeStream(of: RemoteChatEvent.self)
        chatContinuation = continuation
        return stream
    }
    func emitChat(_ event: RemoteChatEvent) { chatContinuation?.yield(event) }
    func sendChat(hubId: String, sessionId: String, text: String) { chatSent.append(text) }
    func respondPrompt(hubId: String, sessionId: String, itemId: String, revision: Int, answer: RemotePromptAnswer) {
        answers.append((itemId, revision, answer))
    }
}

@MainActor
struct RemoteControllerStoreTests {
    @Test func startedSessionBecomesTheSelection() async {
        let fake = FakeController()
        let store = RemoteControllerStore(service: fake)
        await store.startSession(hubId: "build", checkoutPath: "/p", kind: .shell)
        #expect(store.selectedSession == RemoteSessionRef(hubId: "build", sessionId: "new-session"))
        #expect(store.selectedHubId == "build")
    }

    @Test func failedStartShowsTheReason() async {
        let fake = FakeController()
        fake.startError = RemoteControllerError.failed("unknown_repo")
        let store = RemoteControllerStore(service: fake)
        await store.startSession(hubId: "build", checkoutPath: "/p", kind: .shell)
        #expect(store.lastError == "The hub refused: unknown_repo")
        #expect(store.selectedSession == nil)
    }

    @Test func selectionClearsWhenTheTerminalDisappearsFromTheHub() async throws {
        let fake = FakeController()
        let store = RemoteControllerStore(service: fake)
        store.start()
        store.select(RemoteSessionRef(hubId: "build", sessionId: "s1"))
        fake.emit(.linkChanged(hubId: "build", .connected))
        fake.emit(.snapshotChanged(hubId: "build", RemoteHubSnapshot(sessions: [
            RemoteSessionInfo(id: "s1", repoName: "lumi", status: "idle"),
        ])))
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.selectedSession != nil)
        fake.emit(.snapshotChanged(hubId: "build", RemoteHubSnapshot(sessions: [])))
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.selectedSession == nil)
    }

    /// ⌘T: seçili uzak terminalin checkout'unda yeni Claude; serbest terminalde/seçimsiz no-op.
    @Test func commandTOpensClaudeBesideTheSelectedTerminal() async throws {
        let fake = FakeController()
        let store = RemoteControllerStore(service: fake)
        store.start()
        #expect(!store.startSessionBesideSelection())
        fake.emit(.linkChanged(hubId: "build", .connected))
        fake.emit(.snapshotChanged(hubId: "build", RemoteHubSnapshot(
            sessions: [RemoteSessionInfo(id: "s1", repoName: "lumi", status: "idle"),
                       RemoteSessionInfo(id: "loose", repoName: "", status: "idle")],
            projects: [RemoteProjectNode(path: "/p", name: "lumi", checkouts: [
                RemoteCheckoutNode(path: "/p/wt", title: "wt", kind: "worktree", agentIds: ["s1"]),
            ])])))
        try await Task.sleep(for: .milliseconds(30))
        store.select(RemoteSessionRef(hubId: "build", sessionId: "loose"))
        #expect(!store.startSessionBesideSelection())
        store.select(RemoteSessionRef(hubId: "build", sessionId: "s1"))
        #expect(store.startSessionBesideSelection())
        try await Task.sleep(for: .milliseconds(30))
        #expect(fake.startedAt.map(\.path) == ["/p/wt"])
        #expect(fake.startedAt.first?.kind == .claude(model: nil))
        #expect(store.selectedSession == RemoteSessionRef(hubId: "build", sessionId: "new-session"))
    }

    @Test func rejectionReasonsReadAsSentences() {
        #expect(RemoteControllerStore.describeRejection("wrong_password") == "Wrong password.")
        #expect(RemoteControllerStore.describeRejection("weird").contains("weird"))
    }
}

// MARK: - Claude chat görünümü (karar 143 ek)

private let chatRef = RemoteSessionRef(hubId: "build", sessionId: "s1")

private func message(_ id: String, _ role: ChatRole, _ text: String) -> ChatMessage {
    ChatMessage(id: id, role: role, blocks: [.text(text, presentation: nil)], timestampMs: nil, turnId: nil)
}

private func approval(_ itemId: String, state: ChatPromptState = .pending) -> ChatPrompt {
    ChatPrompt(itemId: itemId, revision: 1, kind: .approval, title: "Bash(make)", detail: nil,
               options: [ChatPromptOption(id: "yes", label: "Yes", description: nil)],
               state: state, selectedOptionId: nil)
}

@MainActor
struct RemoteChatSessionTests {
    @Test func snapshotAnchorsAppendsAndUnanchoredAppendsAreDropped() async throws {
        let fake = FakeController()
        let chat = RemoteChatSession(ref: chatRef, service: fake)
        chat.start()
        #expect(chat.isSyncing)
        chat.apply(.append([message("x", .assistant, "çapasız")], afterId: nil))
        #expect(chat.messages.isEmpty)

        chat.apply(.snapshot([message("u1", .user, "build et"), message("a1", .assistant, "Başlıyorum")], hasEarlier: true))
        #expect(!chat.isSyncing)
        #expect(chat.hasEarlier)
        chat.apply(.append([message("a1", .assistant, "Başlıyorum…"), message("a2", .assistant, "Bitti")], afterId: nil))
        #expect(chat.messages.map(\.id) == ["u1", "a1", "a2"])
        #expect(chat.messages[1] == message("a1", .assistant, "Başlıyorum…"))
    }

    @Test func sentMessageShowsUntilTheTranscriptEchoesIt() {
        let fake = FakeController()
        let chat = RemoteChatSession(ref: chatRef, service: fake)
        chat.start()
        chat.apply(.snapshot([message("a0", .assistant, "Merhaba")], hasEarlier: false))
        chat.send("  testleri koş \n")
        #expect(fake.chatSent == ["testleri koş"])
        #expect(chat.turns.map(\.message.role) == [.assistant, .user])

        chat.apply(.append([message("u1", .user, "testleri koş")], afterId: nil))
        #expect(chat.turns.map(\.id) == ["a0", "u1"], "iyimser kopya transcript'e düşünce kalkar")
    }

    @Test func reopeningAsksOnlyForWhatIsMissing() {
        let fake = FakeController()
        let chat = RemoteChatSession(ref: chatRef, service: fake)
        chat.start()
        chat.apply(.snapshot([message("m1", .user, "a"), message("m2", .assistant, "b")], hasEarlier: false))
        chat.stop()
        chat.start()
        #expect(fake.chatSubscriptions == [nil, "m2"])
        chat.apply(.append([message("m3", .assistant, "c")], afterId: "m2"))
        #expect(chat.messages.map(\.id) == ["m1", "m2", "m3"])
        #expect(!chat.isSyncing)
        // Başka imleçli cevap (listede olmayan çapa) yok sayılır.
        chat.apply(.append([message("zz", .assistant, "?")], afterId: "yok"))
        #expect(chat.messages.map(\.id) == ["m1", "m2", "m3"])
    }

    @Test func promptsComeAndGoWithTheHubsBroadcast() {
        let fake = FakeController()
        let chat = RemoteChatSession(ref: chatRef, service: fake)
        chat.apply(.prompt(approval("p1")))
        #expect(chat.activePrompt?.itemId == "p1")
        chat.respond(to: approval("p1"), with: .option("yes"))
        #expect(fake.answers.first?.answer == .option("yes"))
        #expect(chat.activePrompt != nil, "kart iyimser kapanmaz")
        chat.apply(.prompt(approval("p1", state: .resolved)))
        #expect(chat.activePrompt == nil)
    }

    @Test func stopSendsEscOnceAndClearsWhenTheTurnEnds() {
        let fake = FakeController()
        let chat = RemoteChatSession(ref: chatRef, service: fake)
        chat.interrupt()
        #expect(fake.inputs.isEmpty, "boştaki Claude'a Esc gitmez")
        chat.apply(.status(ChatTurnStatus(working: true, startedAtMs: 100, tool: "Bash")))
        chat.interrupt()
        chat.interrupt()
        #expect(fake.inputs == [Data([0x1B])])
        #expect(chat.isStopping)
        chat.apply(.status(.idle))
        #expect(!chat.isStopping)
    }

    @Test func storeKeepsOneChatPerTerminalAndDropsItWhenTheTerminalCloses() async throws {
        let fake = FakeController()
        let store = RemoteControllerStore(service: fake)
        store.start()
        #expect(store.chatSession(chatRef) === store.chatSession(chatRef))
        let first = store.chatSession(chatRef)
        fake.emit(.linkChanged(hubId: "build", .connected))
        fake.emit(.snapshotChanged(hubId: "build", RemoteHubSnapshot(sessions: [])))
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.chatSession(chatRef) !== first)
    }
}
