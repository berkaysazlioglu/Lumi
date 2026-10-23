import XCTest
import LumiWire
@testable import LumiMobileKit

/// Decision 130: a (re)subscribe never wipes the chat on screen; it syncs.
@MainActor
final class AppModelChatSyncTests: XCTestCase {

    private func makeModel() -> (AppModel, FakeRelayClient) {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)
        model.chatSyncTimeout = .milliseconds(30)
        model.chatReleaseDelay = .milliseconds(40)
        return (model, client)
    }

    private func msg(_ id: String, _ text: String = "hi") -> ChatMessage {
        ChatMessage(id: id, role: .assistant, blocks: [.text(text, presentation: nil)], timestampMs: nil, turnId: nil)
    }

    private func chatMeta(_ id: String) -> SessionMeta {
        SessionMeta(id: id, repoName: "lumi", status: "idle", title: nil, model: nil,
                    cols: 80, rows: 24, kind: "chat")
    }

    private func subscribeCount(_ client: FakeRelayClient, _ sid: String) -> Int {
        client.sentFrames.filter { $0.contains(#""type":"subscribe""#) && $0.contains(sid) }.count
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testResubscribeKeepsMessagesUntilSnapshotArrives() async {
        let (model, _) = makeModel()
        model.handle(.chat(sessionId: "s1", messages: [msg("m1")]))
        model.subscribeChat("s1")
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["m1"], "subscribe must not clear the chat")
        XCTAssertTrue(model.chatSyncing.contains("s1"))
        model.handle(.chat(sessionId: "s1", messages: [msg("m1"), msg("m2")]))
        XCTAssertFalse(model.chatSyncing.contains("s1"))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["m1", "m2"])
    }

    func testMissingSnapshotRetriesThenGivesUp() async {
        let (model, client) = makeModel()
        await model.start()
        client.emit(.stateChanged(.connected))
        await waitUntil { model.connection == .connected }
        model.subscribeChat("s1")
        await waitUntil { !model.chatSyncing.contains("s1") }
        XCTAssertEqual(subscribeCount(client, "s1"), model.chatSyncMaxAttempts)
        XCTAssertFalse(model.chatSyncing.contains("s1"), "sync gives up after the last attempt")
    }

    func testMacSessionsRetryAGivenUpSync() async {
        let (model, client) = makeModel()
        await model.start()
        client.emit(.stateChanged(.connected))
        await waitUntil { model.connection == .connected }
        model.subscribeChat("s1")
        await waitUntil { !model.chatSyncing.contains("s1") }
        let before = subscribeCount(client, "s1")
        model.handle(.sessions([chatMeta("s1")]))
        await waitUntil { subscribeCount(client, "s1") > before }
        XCTAssertTrue(model.chatSyncing.contains("s1"))
    }

    func testLeavingChatReleasesMacTailLazily() async throws {
        let (model, client) = makeModel()
        model.handle(.sessions([chatMeta("s1")]))
        model.subscribeChat("s1")
        model.leaveSession("s1")
        XCTAssertNil(model.activeSessionId, "selection drops at once")
        XCTAssertFalse(client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) })
        await waitUntil { client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) } }
        XCTAssertTrue(client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) })
    }

    func testReenteringChatCancelsPendingRelease() async throws {
        let (model, client) = makeModel()
        model.handle(.sessions([chatMeta("s1")]))
        model.subscribeChat("s1")
        model.leaveSession("s1")
        model.subscribeChat("s1")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) })
        XCTAssertEqual(model.activeSessionId, "s1")
    }

    func testLeavingTerminalMirrorUnsubscribesAtOnce() async {
        let (model, client) = makeModel()
        model.subscribe("t1")
        model.leaveSession("t1")
        await waitUntil { client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) } }
        XCTAssertTrue(client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) && $0.contains("t1") })
    }

    func testCappedSnapshotFlagsEarlierMessages() {
        let (model, _) = makeModel()
        let frame = #"{"v":1,"type":"chat","payload":{"sessionId":"s1","hasEarlier":true,"messages":[]}}"#
        guard let decoded = PhoneProtocol.decodeServerMessage(frame) else { return XCTFail("decode") }
        model.handle(decoded)
        XCTAssertTrue(model.chatHasEarlier.contains("s1"))
        model.handle(.chat(sessionId: "s1", messages: [msg("m1")]))
        XCTAssertFalse(model.chatHasEarlier.contains("s1"), "a full snapshot clears the flag")
    }

    // MARK: Delta sync (phase 4)

    func testSubscribeSendsLastMessageIdAsCursor() async {
        let (model, client) = makeModel()
        model.handle(.chat(sessionId: "s1", messages: [msg("u1"), msg("u2")]))
        model.subscribeChat("s1")
        await waitUntil { client.sentFrames.contains { $0.contains(#""afterId":"u2""#) } }
        XCTAssertTrue(client.sentFrames.contains { $0.contains(#""afterId":"u2""#) })
    }

    func testUnstableIdIsNotSentAsCursor() async {
        let (model, client) = makeModel()
        model.handle(.chat(sessionId: "s1", messages: [msg("idx-4")]))
        model.subscribeChat("s1")
        await waitUntil { subscribeCount(client, "s1") > 0 }
        XCTAssertFalse(client.sentFrames.contains { $0.contains("afterId") })
    }

    func testDeltaReplyAppendsAndEndsSync() {
        let (model, _) = makeModel()
        model.handle(.chat(sessionId: "s1", messages: [msg("u1")]))
        model.subscribeChat("s1")
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u2")], afterId: "u1"))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1", "u2"])
        XCTAssertFalse(model.chatSyncing.contains("s1"))
        model.subscribeChat("s1")
        model.handle(.chatAppend(sessionId: "s1", messages: [], afterId: "u2"))
        XCTAssertFalse(model.chatSyncing.contains("s1"), "an empty reply means up to date")
    }

    func testDeltaReplyForAnotherListIsIgnored() {
        let (model, _) = makeModel()
        model.handle(.chat(sessionId: "s1", messages: [msg("u1")]))
        model.subscribeChat("s1")
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("x2")], afterId: "x1"))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1"], "a gap must not be papered over")
        XCTAssertTrue(model.chatSyncing.contains("s1"))
    }

    /// Field bug (build 495): a fresh app run received the tail of a subscribe made by an
    /// earlier run, built a list from it, and the delta subscribe then called it complete.
    func testAppendWithoutSnapshotIsDroppedSoSubscribeFetchesInFull() async {
        let (model, client) = makeModel()
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u7"), msg("u8")]))
        XCTAssertTrue(model.chatMessages("s1").isEmpty, "an unanchored append must not seed the list")
        model.subscribeChat("s1")
        await waitUntil { subscribeCount(client, "s1") > 0 }
        XCTAssertFalse(client.sentFrames.contains { $0.contains("afterId") }, "no cursor → full snapshot")
    }

    func testAppendsAfterDisconnectWaitForTheDeltaReply() async {
        let (model, client) = makeModel()
        await model.start()
        client.emit(.stateChanged(.connected))
        await waitUntil { model.connection == .connected }
        model.subscribeChat("s1")
        model.handle(.chat(sessionId: "s1", messages: [msg("u1")]))
        client.emit(.stateChanged(.disconnected))
        await waitUntil { model.connection == .disconnected }
        client.emit(.stateChanged(.connected))
        await waitUntil { model.connection == .connected }
        // u2 went out while the socket was down; u3 arrives before the delta reply.
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u3")]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1"], "a post-gap append would hide u2")
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u2"), msg("u3")], afterId: "u1"))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1", "u2", "u3"])
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u4")]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1", "u2", "u3", "u4"], "live again")
    }

    func testDeltaReplyReplacesRowsPastTheCursorInOrder() {
        let (model, _) = makeModel()
        model.handle(.chat(sessionId: "s1", messages: [msg("u1"), msg("u3")]))
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u2"), msg("u3")], afterId: "u1"))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1", "u2", "u3"])
    }

    func testUnsubscribedChatStopsTakingAppends() async {
        let (model, client) = makeModel()
        model.handle(.sessions([chatMeta("s1")]))
        model.subscribeChat("s1")
        model.handle(.chat(sessionId: "s1", messages: [msg("u1")]))
        model.leaveSession("s1")
        await waitUntil { client.sentFrames.contains { $0.contains(#""type":"unsubscribe""#) } }
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("u2")]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["u1"])
    }

    func testDeltaFrameDecodesAfterId() {
        let frame = #"{"v":1,"type":"chat_append","payload":{"sessionId":"s1","afterId":"u1","messages":[]}}"#
        guard case let .chatAppend(sid, messages, afterId)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("decode")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(afterId, "u1")
    }
}
