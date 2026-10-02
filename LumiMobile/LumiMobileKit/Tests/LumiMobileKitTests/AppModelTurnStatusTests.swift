import XCTest
@testable import LumiMobileKit
import LumiWire

@MainActor
final class AppModelTurnStatusTests: XCTestCase {
    private func makeModel() -> AppModel {
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        return AppModel(client: FakeRelayClient(), store: store)
    }

    private func meta(_ id: String, repo: String, _ status: String = "idle") -> SessionMeta {
        SessionMeta(id: id, repoName: repo, status: status, title: nil, model: nil, cols: 80, rows: 24)
    }

    func testChatStatusMergesIntoTurnStatus() {
        let model = makeModel()
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 10, tool: "Read")))
        XCTAssertEqual(model.turnStatus["s1"], ChatTurnStatus(working: true, startedAtMs: 10, tool: "Read"))
    }

    func testActiveSessionDisappearClearsTurnStatus() {
        let model = makeModel()
        // s1 is the active session + turnStatus is populated.
        model.handle(.sessions([meta("s1", repo: "lumi", "working")]))
        model.subscribe("s1")
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 10, tool: "Read")))
        XCTAssertNotNil(model.turnStatus["s1"])
        // When s1 drops from the list (closed/deleted), turnStatus should be cleared.
        model.handle(.sessions([]))
        XCTAssertNil(model.turnStatus["s1"])
    }

    // MARK: Decision 96 — Stop sends Esc, "Stopping…" + local fallback

    private func prompt(_ id: String, state: ChatPromptState = .pending) -> ChatPrompt {
        ChatPrompt(itemId: id, revision: 0, kind: .approval, title: "t", detail: nil,
                   options: [ChatPromptOption(id: "allow", label: "Allow", description: nil)],
                   state: state, selectedOptionId: nil)
    }

    /// Decodes the last sent `input` frame's base64 `data` payload (the frame is a JSON
    /// envelope string — see `PhoneProtocol.inputFrame` / `FakeRelayClient.sentFrames`).
    private func lastInputBytes(_ client: FakeRelayClient) async -> Data? {
        for raw in client.sentFrames.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  json["type"] as? String == "input",
                  let payload = json["payload"] as? [String: Any],
                  let base64 = payload["data"] as? String else { continue }
            return Data(base64Encoded: base64)
        }
        return nil
    }

    func testRequestStopSendsEscAndMarksStopping() async throws {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.requestStop("s1")
        XCTAssertTrue(model.stoppingSessions.contains("s1"))
        try await Task.sleep(for: .milliseconds(50))
        let sent = await lastInputBytes(client)
        XCTAssertEqual(sent, Data([0x1B]))
    }

    func testIdleStatusClearsStopping() {
        let model = makeModel()
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.requestStop("s1")
        model.handle(.chatStatus(sessionId: "s1", status: .idle))
        XCTAssertFalse(model.stoppingSessions.contains("s1"))
    }

    func testStopFallbackClosesTurnLocally() async throws {
        let model = makeModel()
        model.stopFallbackDelay = .milliseconds(20)
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.handle(.prompt(sessionId: "s1", prompt: prompt("p1")))
        model.requestStop("s1")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.turnStatus["s1"]?.working, false)
        XCTAssertFalse(model.stoppingSessions.contains("s1"))
        XCTAssertTrue(model.prompts["s1"]?.isEmpty ?? true)
    }

    func testNewTurnDuringStoppingIsNotClobberedByFallback() async throws {
        let model = makeModel()
        model.stopFallbackDelay = .milliseconds(20)
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.requestStop("s1")
        model.handle(.chatStatus(sessionId: "s1", status: .idle))
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 2, tool: nil)))
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.turnStatus["s1"]?.working, true)
    }
}
