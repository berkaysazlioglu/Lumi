import Testing
import Foundation
@testable import LumiState
import LumiKit

// Claude terminalinin remote araçları (karar 143, Faz 5).

@MainActor
private final class ScriptedController: RemoteControllerServicing {
    var directoryState: RemoteConnectionState = .connected
    var hubs: [RemoteHubInfo] = [
        RemoteHubInfo(id: "hub-build", name: "Build Mac", isOnline: true),
        RemoteHubInfo(id: "hub-office", name: "Office", isOnline: false),
    ]
    var links: [String: RemoteHubLinkState] = ["hub-build": .connected]
    var snapshots: [String: RemoteHubSnapshot] = [
        "hub-build": RemoteHubSnapshot(
            sessions: [
                RemoteSessionInfo(id: "aaaaaaaa-1111", title: "Fix build", repoName: "game", status: "working", provider: .claude),
                RemoteSessionInfo(id: "bbbbbbbb-2222", repoName: "game", status: "idle"),
            ],
            projects: [RemoteProjectNode(path: "/w/game", name: "Game", checkouts: [
                RemoteCheckoutNode(path: "/w/game", title: "main", kind: "root", branch: "main", agentIds: ["aaaaaaaa-1111", "bbbbbbbb-2222"]),
            ])]),
    ]
    var reading: RemoteTerminalReading = .screen("")
    var connectResult: RemoteHubLinkState = .connected
    private(set) var sent: [(String, String, Bool)] = []
    private(set) var started: [(String, RemoteSessionKind, String)] = []

    func linkState(_ hubId: String) -> RemoteHubLinkState { links[hubId] ?? .disconnected }
    func snapshot(_ hubId: String) -> RemoteHubSnapshot? { snapshots[hubId] }
    func configure(endpoint: RelayEndpoint?, identity: RemoteControllerIdentity) {}
    func stop() {}
    func connect(hubId: String, password: String?, remember: Bool) async { links[hubId] = connectResult }
    func disconnect(hubId: String) {}
    func hasRememberedPassword(hubId: String) async -> Bool { false }
    func terminalOutput(hubId: String, sessionId: String) -> AsyncStream<RemoteTerminalChunk> { AsyncStream { $0.finish() } }
    func sendInput(hubId: String, sessionId: String, data: Data) {}
    func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind, prompt: String) async throws -> String? {
        started.append((checkoutPath, kind, prompt))
        return "cccccccc-3333"
    }
    func closeSession(hubId: String, sessionId: String) async throws {}
    func sendText(hubId: String, sessionId: String, text: String, submit: Bool) async throws { sent.append((sessionId, text, submit)) }
    func readTerminal(hubId: String, sessionId: String) async throws -> RemoteTerminalReading { reading }
    func chatEvents(hubId: String, sessionId: String, afterId: String?) -> AsyncStream<RemoteChatEvent> { AsyncStream { $0.finish() } }
    func sendChat(hubId: String, sessionId: String, text: String) {}
    func respondPrompt(hubId: String, sessionId: String, itemId: String, revision: Int, answer: RemotePromptAnswer) {}
    func events() -> AsyncStream<RemoteControllerEvent> { AsyncStream { $0.finish() } }
}

@MainActor
struct RemoteMCPToolboxTests {
    private func call(_ toolbox: RemoteMCPToolbox, _ name: String, _ args: [String: Any] = [:]) async -> OrchestratorToolResult {
        await toolbox.call(name: name, arguments: try! JSONSerialization.data(withJSONObject: args))
    }

    @Test func listsHubsWithTheirConnection() async {
        let toolbox = RemoteMCPToolbox(controller: ScriptedController())
        let result = await call(toolbox, RemoteMCPTools.listHubs)
        #expect(!result.isError)
        #expect(result.text.contains("\"Build Mac\""))
        #expect(result.text.contains("\"connected\""))
        #expect(result.text.contains("\"not connected\""))
    }

    @Test func hubsResolveByNameCaseInsensitivelyOrById() async {
        let toolbox = RemoteMCPToolbox(controller: ScriptedController())
        #expect(!(await call(toolbox, RemoteMCPTools.listTerminals, ["hub": "build mac"])).isError)
        #expect(!(await call(toolbox, RemoteMCPTools.listTerminals, ["hub": "hub-build"])).isError)
        let unknown = await call(toolbox, RemoteMCPTools.listTerminals, ["hub": "Nope"])
        #expect(unknown.isError && unknown.text.contains("No hub named Nope"))
        let offline = await call(toolbox, RemoteMCPTools.listTerminals, ["hub": "Office"])
        #expect(offline.isError && offline.text.contains("remote_connect_hub"))
    }

    @Test func listTerminalsShowsCheckoutPathsAndStatuses() async {
        let toolbox = RemoteMCPToolbox(controller: ScriptedController())
        let result = await call(toolbox, RemoteMCPTools.listTerminals, ["hub": "Build Mac"])
        #expect(result.text.contains("\"path\" : \"/w/game\""))
        #expect(result.text.contains("\"status\" : \"running\""))
        #expect(result.text.contains("\"agent\" : \"shell\""))
    }

    @Test func connectAsksForThePasswordWhenNoneIsSaved() async {
        let controller = ScriptedController()
        controller.connectResult = .rejected(reason: "password_required")
        controller.hubs[1].isOnline = true
        let result = await call(RemoteMCPToolbox(controller: controller), RemoteMCPTools.connectHub, ["hub": "Office"])
        #expect(result.isError && result.text.hasPrefix("password required"))
    }

    @Test func readReturnsTheTranscriptOrTheScreenTail() async {
        let controller = ScriptedController()
        let toolbox = RemoteMCPToolbox(controller: controller)
        controller.reading = .transcript([
            ChatMessage(id: "1", role: .user, blocks: [.text("Update the build", presentation: nil)], timestampMs: nil, turnId: nil),
            ChatMessage(id: "2", role: .assistant, blocks: [.text("Done.", presentation: nil)], timestampMs: nil, turnId: nil),
        ])
        let transcript = await call(toolbox, RemoteMCPTools.readTerminal, ["hub": "Build Mac", "terminal_id": "aaaaaaaa"])
        #expect(transcript.text.contains("Build Mac / game / Fix build — running"))
        #expect(transcript.text.contains("[assistant] Done."))

        controller.reading = .screen("line 1\nline 2\nline 3   \n\n\n")
        let screen = await call(toolbox, RemoteMCPTools.readTerminal, ["hub": "Build Mac", "terminal_id": "bbbbbbbb-2222", "limit": 2])
        #expect(screen.text.hasSuffix("Last screen lines:\nline 2\nline 3"))
    }

    @Test func terminalIdNeedsAUniquePrefixOfSixCharacters() async {
        let toolbox = RemoteMCPToolbox(controller: ScriptedController())
        let short = await call(toolbox, RemoteMCPTools.readTerminal, ["hub": "Build Mac", "terminal_id": "aaa"])
        #expect(short.isError && short.text.contains("at least 6"))
    }

    @Test func sendSubmitsByDefault() async {
        let controller = ScriptedController()
        let toolbox = RemoteMCPToolbox(controller: controller)
        _ = await call(toolbox, RemoteMCPTools.sendToTerminal, ["hub": "Build Mac", "terminal_id": "aaaaaaaa-1111", "text": "git pull"])
        _ = await call(toolbox, RemoteMCPTools.sendToTerminal, ["hub": "Build Mac", "terminal_id": "aaaaaaaa-1111", "text": "y", "submit": false])
        #expect(controller.sent.map(\.2) == [true, false])
        let empty = await call(toolbox, RemoteMCPTools.sendToTerminal, ["hub": "Build Mac", "terminal_id": "aaaaaaaa-1111", "text": ""])
        #expect(empty.isError)
    }

    @Test func startOnlyAcceptsKnownCheckoutsAndModels() async {
        let controller = ScriptedController()
        let toolbox = RemoteMCPToolbox(controller: controller)
        let started = await call(toolbox, RemoteMCPTools.startTerminal, [
            "hub": "Build Mac", "checkout_path": "/w/game", "prompt": "run the update", "model": "opus",
        ])
        #expect(started.text.contains("cccccccc-3333"))
        #expect(controller.started.first?.1 == .claude(model: .opus))
        #expect(controller.started.first?.2 == "run the update")

        let unknown = await call(toolbox, RemoteMCPTools.startTerminal, ["hub": "Build Mac", "checkout_path": "/etc"])
        #expect(unknown.isError && unknown.text.contains("not a checkout"))
        let badModel = await call(toolbox, RemoteMCPTools.startTerminal, ["hub": "Build Mac", "checkout_path": "/w/game", "model": "gpt"])
        #expect(badModel.isError)
        let shell = await call(toolbox, RemoteMCPTools.startTerminal, ["hub": "Build Mac", "checkout_path": "/w/game", "kind": "shell", "prompt": "ignored"])
        #expect(!shell.isError)
        #expect(controller.started.last?.1 == .shell && controller.started.last?.2 == "")
    }
}
