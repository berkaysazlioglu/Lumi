import Testing
import Foundation
@testable import LumiRemote
import LumiKit

// Hub'ın ürettiği frame'ler (RemoteProtocol) ↔ controller'ın çözümleyicisi (docs/design/08).
struct RemoteControllerWireTests {
    @Test func sessionsRoundTripFromTheHubEncoder() {
        let meta = SessionMeta(
            id: "s1", repoName: "lumi", status: "working", title: "Fix bug", cols: 80, rows: 24,
            kind: "chat", provider: "claude", lastActivityAt: 1_700_000_000_000, awaitingDecision: true)
        let decoded = RemoteControllerWire.sessions(RemoteProtocol.sessionsPayload([meta]))
        #expect(decoded == [RemoteSessionInfo(
            id: "s1", title: "Fix bug", repoName: "lumi", status: "working", provider: .claude,
            awaitingDecision: true, lastActivityAt: Date(timeIntervalSince1970: 1_700_000_000))])
    }

    @Test func projectTreeDecodesCheckoutsAppearanceAndOthers() {
        let payload = RemoteProtocol.projectsPayload(
            projects: [[
                "name": "Lumi", "path": "/p/lumi",
                "appearance": ["color": "blue", "icon": "emoji:🚀"],
                "checkouts": [
                    ["kind": "root", "title": "main", "scm": "git", "path": "/p/lumi", "branch": "main", "agentIds": ["s1"]],
                    ["title": "bozuk — yolu yok"],
                ],
            ], ["path": "/eksik-ad"]],
            others: [["path": "/tmp/x", "label": "x", "agentIds": ["s2"]]],
            addable: [])
        let tree = RemoteControllerWire.tree(payload)
        #expect(tree.projects == [RemoteProjectNode(
            path: "/p/lumi", name: "Lumi",
            checkouts: [RemoteCheckoutNode(path: "/p/lumi", title: "main", kind: "root", branch: "main", agentIds: ["s1"])],
            color: "blue", icon: "emoji:🚀")])
        #expect(tree.others == [RemoteOtherGroup(path: "/tmp/x", label: "x", agentIds: ["s2"])])
    }

    @Test func terminalFramesRoundTrip() throws {
        let snapshot = try #require(RemoteControllerWire.terminalChunk(
            type: "scrollback",
            payload: RemoteProtocol.scrollbackPayload(sessionId: "s1", seq: 0, cols: 120, rows: 40, data: Data("A".utf8))))
        #expect(snapshot.sessionId == "s1")
        #expect(snapshot.chunk == RemoteTerminalChunk(data: Data("A".utf8), cols: 120, rows: 40, isSnapshot: true))
        let live = try #require(RemoteControllerWire.terminalChunk(
            type: "data", payload: RemoteProtocol.dataPayload(sessionId: "s1", seq: 3, data: Data("B".utf8))))
        #expect(live.chunk == RemoteTerminalChunk(data: Data("B".utf8), isSnapshot: false))
        #expect(RemoteControllerWire.terminalChunk(type: "chat", payload: [:]) == nil)
    }

    @Test func hubListHidesThisMacAndDropsBrokenEntries() {
        let hubs = RemoteControllerWire.hubs([
            "hubs": [
                ["hubId": "me", "name": "This Mac", "online": true],
                ["hubId": "build", "name": "Build Mac", "online": true, "lastSeenAt": 2_000, "controllerCount": 1],
                ["name": "kimliksiz"],
            ],
        ], excluding: "me")
        #expect(hubs == [RemoteHubInfo(id: "build", name: "Build Mac", isOnline: true,
                                       lastSeenAt: Date(timeIntervalSince1970: 2), controllerCount: 1)])
    }

    @Test func startSessionCommandMatchesTheHubHandler() {
        let claude = RemoteControllerWire.startSessionCommand(commandId: "c1", checkoutPath: "/p", kind: .claude(model: .opus))
        #expect(claude["kind"] as? String == "chat")
        #expect(claude["model"] as? String == "opus")
        #expect(claude["repoPath"] as? String == "/p")
        let shell = RemoteControllerWire.startSessionCommand(commandId: "c2", checkoutPath: "/p", kind: .shell)
        #expect(shell["kind"] as? String == "shell")
        #expect(shell["model"] == nil)
    }
}
