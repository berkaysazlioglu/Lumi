import XCTest
@testable import LumiMobileKit

// ---------------------------------------------------------------------------
// EndToEndWireTests — Phone-side E2E wire test
//
// Verifies the full PhoneProtocol decode → AppModel routing chain by injecting
// COMPLETE JSON envelope strings (as produced by the relay) into a real AppModel,
// without connecting to a real relay.
//
// Fake layer: FakeRelayClient (from RelayClientTests) — incoming frames are pushed
// from outside, outgoing frames are recorded.
// Real layer: AppModel + PhoneProtocol (source unchanged).
//
// Covered scenario (task-12-brief §Part B):
//   1. welcome/sessions message → model.sessions is populated.
//   2. model.subscribe("s1") → subscribe frame is sent to the client.
//   3. scrollback (base64 "SCROLL") + data (base64 "LIVE") → terminalStream
//      delivers them IN ORDER: "SCROLL" then "LIVE".
//   4. model.sendInput("s1", Data("hi")) → input frame is sent to the client,
//      payload contains base64 "aGk=".
// ---------------------------------------------------------------------------

// MARK: - Helpers

/// Injects the given frame string into AppModel as a message arriving from the relay.
@MainActor
private func injectFrame(_ frame: String, into client: FakeRelayClient) {
    if let message = PhoneProtocol.decodeServerMessage(frame) {
        client.emit(.message(message))
    }
}

/// Waits until `condition` is true (up to ~2 s).
@MainActor
private func waitFor(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Waits until a frame containing `needle` appears in `client.sentFrames`.
@MainActor
private func awaitFrame(_ client: FakeRelayClient, containing needle: String) async {
    for _ in 0..<200 where !client.sentFrames.contains(where: { $0.contains(needle) }) {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - Test

@MainActor
final class EndToEndWireTests: XCTestCase {

    // MARK: Step 1: welcome+sessions message — model.sessions is populated

    func testStep1_WelcomeWithSessionsPopulatesModel() {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)

        // Actual wire JSON produced by the relay (envelope {v:1,type,payload}).
        // sessions: SessionMeta array; fields: id, repoName, status, cols, rows.
        let frame = #"""
        {"v":1,"type":"sessions","payload":{"sessions":[
          {"id":"s1","repoName":"lumi","status":"working","cols":220,"rows":50}
        ]}}
        """#

        guard let msg = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("PhoneProtocol could not decode the frame")
        }
        model.handle(msg)

        XCTAssertEqual(model.sessions.count, 1)
        let meta = model.sessions[0]
        XCTAssertEqual(meta.id, "s1")
        XCTAssertEqual(meta.repoName, "lumi")
        XCTAssertEqual(meta.status, "working")
        XCTAssertEqual(meta.cols, 220)
        XCTAssertEqual(meta.rows, 50)
        XCTAssertTrue(model.macOnline, "sessions message comes from the Mac → macOnline true")
    }

    // MARK: Step 2: subscribe → client sends subscribe frame

    func testStep2_SubscribeSendsSubscribeFrame() async {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)

        model.subscribe("s1")
        XCTAssertEqual(model.activeSessionId, "s1")

        await awaitFrame(client, containing: #""type":"subscribe""#)

        let subscribeFrames = client.sentFrames.filter { $0.contains(#""type":"subscribe""#) }
        XCTAssertFalse(subscribeFrames.isEmpty, "subscribe frame must be sent")
        XCTAssertTrue(subscribeFrames.contains { $0.contains("s1") }, "must contain s1 sessionId")
    }

    // MARK: Step 3: scrollback + data → terminalStream delivers in order

    func testStep3_ScrollbackThenDataArrivedInOrder() async throws {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)

        // Subscribe: sets activeSessionId and initializes the replay buffer.
        model.subscribe("s1")

        // Actual wire JSON produced by the relay.
        // "SCROLL" → base64 = "U0NST0xM"
        let scrollB64 = Data("SCROLL".utf8).base64EncodedString()
        let scrollbackFrame = """
        {"v":1,"type":"scrollback","payload":{"sessionId":"s1","seq":0,"cols":80,"rows":24,"data":"\(scrollB64)"}}
        """
        // "LIVE" → base64 = "TElWRQ=="
        let liveB64 = Data("LIVE".utf8).base64EncodedString()
        let dataFrame = """
        {"v":1,"type":"data","payload":{"sessionId":"s1","seq":1,"data":"\(liveB64)"}}
        """

        // scrollback arrived before the view connects to the stream → buffered for replay.
        guard let scrollMsg = PhoneProtocol.decodeServerMessage(scrollbackFrame) else {
            return XCTFail("scrollback frame could not be decoded")
        }
        model.handle(scrollMsg)

        // Now the view connects to the stream → buffered scrollback is replayed first.
        let stream = model.terminalStream("s1")

        // Send the live data chunk.
        guard let dataMsg = PhoneProtocol.decodeServerMessage(dataFrame) else {
            return XCTFail("data frame could not be decoded")
        }
        model.handle(dataMsg)

        // Collect 2 chunks from the stream and verify order.
        var chunks: [TerminalChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
            if chunks.count == 2 { break }
        }

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].bytes, Data("SCROLL".utf8), "first chunk must be scrollback")
        XCTAssertEqual(chunks[0].seq, 0)
        XCTAssertEqual(chunks[0].cols, 80)
        XCTAssertEqual(chunks[0].rows, 24)
        XCTAssertEqual(chunks[1].bytes, Data("LIVE".utf8), "second chunk must be live data")
    }

    // MARK: Step 4: sendInput → base64 input frame is sent

    func testStep4_SendInputSendsBase64InputFrame() async {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)

        model.sendInput("s1", Data("hi".utf8))

        await awaitFrame(client, containing: #""type":"input""#)

        let inputFrames = client.sentFrames.filter { $0.contains(#""type":"input""#) }
        XCTAssertFalse(inputFrames.isEmpty, "input frame must be sent")

        // "hi" → base64 = "aGk="
        let expectedB64 = Data("hi".utf8).base64EncodedString()  // "aGk="
        XCTAssertEqual(expectedB64, "aGk=")
        XCTAssertTrue(
            inputFrames.contains { $0.contains(expectedB64) },
            "input frame must contain base64('hi') = '\(expectedB64)'"
        )
        XCTAssertTrue(
            inputFrames.contains { $0.contains("s1") },
            "input frame must contain sessionId 's1'"
        )
    }

    // MARK: Projects welcome + standalone projects frame E2E test (Task 10)

    func testProjectsWelcomeAndMessageBuildTree() async {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)
        await model.start()

        // welcome carries projects + addable + a session, exactly as the relay emits.
        injectFrame("""
        {"v":1,"type":"welcome","payload":{
          "macOnline":true,"lastSeenAt":null,
          "sessions":[{"id":"t1","repoName":"unco","status":"idle","cols":80,"rows":24,"provider":"claude","lastActivityAt":1790000000000}],
          "projects":[{"name":"unco","path":"/p/unco","checkouts":[
            {"kind":"original","title":"main","scm":"git","path":"/p/unco","agentIds":["t1"]}]}],
          "addable":[{"name":"orca","path":"/p/orca"}]
        }}
        """, into: client)

        let gotTree = await waitFor { model.projectTree.count == 1 }
        XCTAssertTrue(gotTree, "projectTree should have 1 project after welcome")
        XCTAssertEqual(model.projectTree.count, 1)
        XCTAssertEqual(model.projectTree[0].checkouts[0].agents.map(\.id), ["t1"])
        XCTAssertEqual(model.projectsSnapshot.addable.map(\.name), ["orca"])

        // A later standalone `projects` frame replaces the snapshot.
        injectFrame("""
        {"v":1,"type":"projects","payload":{"projects":[],"addable":[]}}
        """, into: client)

        let cleared = await waitFor { model.projectTree.isEmpty }
        XCTAssertTrue(cleared, "projectTree should be empty after standalone projects frame")
    }

    // MARK: Combined full round-trip E2E test

    func testFullRoundTrip_WelcomeSubscribeScrollbackDataInput() async throws {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)

        // --- Step 1: welcome arrives with sessions ---
        let welcomeFrame = #"""
        {"v":1,"type":"welcome","payload":{"macOnline":true,"lastSeenAt":null,"sessions":[
          {"id":"s1","repoName":"myrepo","status":"idle","cols":200,"rows":50}
        ]}}
        """#
        guard let welcomeMsg = PhoneProtocol.decodeServerMessage(welcomeFrame) else {
            return XCTFail("welcome frame could not be decoded")
        }
        model.handle(welcomeMsg)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].id, "s1")
        XCTAssertEqual(model.sessions[0].repoName, "myrepo")
        XCTAssertTrue(model.macOnline)

        // --- Step 2: phone sends subscribe ---
        model.subscribe("s1")
        await awaitFrame(client, containing: #""type":"subscribe""#)
        XCTAssertTrue(
            client.sentFrames.contains { $0.contains(#""type":"subscribe""#) && $0.contains("s1") },
            "subscribe frame must have been sent"
        )
        client.clearSentFrames()

        // --- Step 3: scrollback arrives (before view connects → in replay buffer) ---
        let scrollB64 = Data("SCROLL".utf8).base64EncodedString()
        let scrollbackFrame = """
        {"v":1,"type":"scrollback","payload":{"sessionId":"s1","seq":0,"cols":80,"rows":24,"data":"\(scrollB64)"}}
        """
        guard let scrollMsg = PhoneProtocol.decodeServerMessage(scrollbackFrame) else {
            return XCTFail("scrollback frame could not be decoded")
        }
        model.handle(scrollMsg)

        // Connect to the view stream.
        let stream = model.terminalStream("s1")

        // Live data chunk arrives.
        let liveB64 = Data("LIVE".utf8).base64EncodedString()
        let dataFrame = """
        {"v":1,"type":"data","payload":{"sessionId":"s1","seq":1,"data":"\(liveB64)"}}
        """
        guard let dataMsg = PhoneProtocol.decodeServerMessage(dataFrame) else {
            return XCTFail("data frame could not be decoded")
        }
        model.handle(dataMsg)

        // Collect 2 chunks from the stream and verify order.
        var chunks: [TerminalChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
            if chunks.count == 2 { break }
        }

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].bytes, Data("SCROLL".utf8), "first chunk must be scrollback")
        XCTAssertEqual(chunks[1].bytes, Data("LIVE".utf8), "second chunk must be live data")

        // --- Step 4: phone sends input → mac receives it ---
        model.sendInput("s1", Data("hi".utf8))
        await awaitFrame(client, containing: #""type":"input""#)

        let inputFrame = client.sentFrames.first { $0.contains(#""type":"input""#) }
        XCTAssertNotNil(inputFrame, "input frame must have been sent")
        XCTAssertTrue(inputFrame!.contains("aGk="), "base64('hi') = 'aGk=' must be in input frame")
        XCTAssertTrue(inputFrame!.contains("s1"), "sessionId 's1' must be in input frame")
    }
}
