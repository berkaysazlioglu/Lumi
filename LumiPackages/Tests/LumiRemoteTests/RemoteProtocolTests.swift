import Foundation
import Testing
import LumiKit
@testable import LumiRemote

@Suite final class RemoteProtocolTests {
    @Test func envelopeRoundTrip() throws {
        let data = try #require(RemoteProtocol.envelope(type: "hello", payload: ["role": "mac", "token": "t-1234567890123456"]))
        let decoded = try #require(RemoteProtocol.decode(data))
        #expect(decoded.type == "hello")
        #expect(decoded.payload["role"] as? String == "mac")
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect((dict["v"] as? Int) == 1)
    }

    @Test func decodeRejectsBadInput() {
        #expect(RemoteProtocol.decode(text: "not json") == nil)
        #expect(RemoteProtocol.decode(text: #"{"v":2,"type":"ping","payload":{}}"#) == nil)
        #expect(RemoteProtocol.decode(text: #"{"v":1,"payload":{}}"#) == nil)
        #expect(RemoteProtocol.decode(text: #"{"v":1,"type":"ping"}"#) == nil)
    }

    @Test func keySequenceMap() {
        #expect(keySequence(for: "1") == "1")
        #expect(keySequence(for: "2") == "2")
        #expect(keySequence(for: "3") == "3")
        #expect(keySequence(for: "enter") == "\r")
        #expect(keySequence(for: "esc") == "\u{1B}")
        #expect(keySequence(for: "rm -rf") == nil)
        #expect(keySequence(for: "f4") == nil)
    }

    @Test func backoffDoublesAndCapsAndResets() {
        var backoff = ReconnectBackoff()
        #expect(backoff.nextDelay() == 1)
        #expect(backoff.nextDelay() == 2)
        #expect(backoff.nextDelay() == 4)
        for _ in 0..<10 { _ = backoff.nextDelay() }
        #expect(backoff.nextDelay() == 60)
        backoff.reset()
        #expect(backoff.nextDelay() == 1)
    }

    @Test func chatPayloadShape() {
        let msg = ChatMessage(id: "m1", role: .assistant,
                              blocks: [.text("hi", presentation: nil)],
                              timestampMs: 5, turnId: nil)
        let p = RemoteProtocol.chatPayload(sessionId: "s1", messages: [msg])
        #expect(p["sessionId"] as? String == "s1")
        let msgs = p["messages"] as? [[String: Any]]
        #expect(msgs?.first?["id"] as? String == "m1")
    }

    @Test func chatAppendPayloadShape() {
        let msg = ChatMessage(id: "m9", role: .assistant,
                              blocks: [.text("done", presentation: nil)],
                              timestampMs: nil, turnId: nil)
        let p = RemoteProtocol.chatAppendPayload(sessionId: "s2", messages: [msg])
        #expect(p["sessionId"] as? String == "s2")
        let msgs = p["messages"] as? [[String: Any]]
        #expect(msgs?.first?["id"] as? String == "m9")
    }

    @Test func subscribeModeDefaultsTerminal() {
        #expect(RemoteProtocol.decodeSubscribeMode(["sessionId": "s"]) == "terminal")
        #expect(RemoteProtocol.decodeSubscribeMode(["sessionId": "s", "mode": "chat"]) == "chat")
    }

    @Test func chatStatusPayloadCarriesSessionIdAndFields() {
        let p = RemoteProtocol.chatStatusPayload(
            sessionId: "s1",
            status: ChatTurnStatus(working: true, startedAtMs: 42, tool: "Read")
        )
        #expect(p["sessionId"] as? String == "s1")
        #expect(p["working"] as? Bool == true)
        #expect(p["startedAtMs"] as? Int == 42)
        #expect(p["tool"] as? String == "Read")
    }

    @Test func sessionMetaToDictIncludesProviderAndActivity() {
        let meta = SessionMeta(id: "t1", repoName: "r", status: "idle", cols: 80, rows: 24,
                               provider: "claude", lastActivityAt: 1_790_000_000_000)
        let d = meta.toDict()
        #expect(d["provider"] as? String == "claude")
        #expect(d["lastActivityAt"] as? Double == 1_790_000_000_000)
    }

    @Test func sessionMetaToDictOmitsNilProvider() {
        let meta = SessionMeta(id: "t1", repoName: "r", status: "idle", cols: 80, rows: 24)
        let d = meta.toDict()
        #expect(d["provider"] == nil)
        #expect(d["lastActivityAt"] == nil)
    }

    @Test func projectsPayloadShape() {
        let payload = RemoteProtocol.projectsPayload(
            projects: [["name": "p", "path": "/p", "checkouts": []]],
            addable: [["name": "orca", "path": "/p/orca"]])
        #expect((payload["projects"] as? [[String: Any]])?.count == 1)
        #expect((payload["addable"] as? [[String: String]])?.first?["path"] == "/p/orca")
    }
}

@Suite struct RemoteProtocolPromptTests {
    @Test func promptPayloadCarriesSessionIdAndItem() {
        let p = ChatPrompt(itemId: "i1", revision: 0, kind: .approval, title: "Bash?", detail: "npm i",
            options: [ChatPromptOption(id: "allow", label: "Allow", description: nil)],
            state: .pending, selectedOptionId: nil)
        let d = RemoteProtocol.promptPayload(sessionId: "s1", prompt: p)
        #expect(d["sessionId"] as? String == "s1")
        #expect(d["itemId"] as? String == "i1")
        #expect(d["kind"] as? String == "approval")
    }
    @Test func decodePromptRespondParsesFields() {
        let r = RemoteProtocol.decodePromptRespond(["sessionId": "s1", "itemId": "i1", "expectedRevision": 2, "optionId": "allow"])
        #expect(r?.sessionId == "s1"); #expect(r?.itemId == "i1")
        #expect(r?.expectedRevision == 2); #expect(r?.optionId == "allow")
    }
    @Test func decodePromptRespondNilOnMissing() {
        #expect(RemoteProtocol.decodePromptRespond(["sessionId": "s1"]) == nil)
    }
}
