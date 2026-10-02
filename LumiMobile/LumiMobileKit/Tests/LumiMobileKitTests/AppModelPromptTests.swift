import XCTest
@testable import LumiMobileKit
import LumiWire

@MainActor
final class AppModelPromptTests: XCTestCase {
    private func makeModel() -> AppModel {
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        return AppModel(client: FakeRelayClient(), store: store)
    }

    private func prompt(_ id: String, state: ChatPromptState) -> ChatPrompt {
        ChatPrompt(itemId: id, revision: 0, kind: .approval, title: "t", detail: nil,
                   options: [ChatPromptOption(id: "allow", label: "Allow", description: nil)],
                   state: state, selectedOptionId: nil)
    }

    private func pendingPrompt(itemId: String) -> ChatPrompt {
        prompt(itemId, state: .pending)
    }

    private func resolved(_ p: ChatPrompt) -> ChatPrompt {
        var copy = p
        copy.state = .resolved
        copy.revision += 1
        return copy
    }

    func testPendingPromptAddedResolvedRemoved() {
        let m = makeModel()
        m.handle(.prompt(sessionId: "s1", prompt: prompt("i1", state: .pending)))
        XCTAssertEqual(m.prompts["s1"]?.count, 1)
        m.handle(.prompt(sessionId: "s1", prompt: prompt("i1", state: .resolved)))
        XCTAssertTrue((m.prompts["s1"] ?? []).isEmpty)   // resolved → dropped
    }

    func testCancelledPromptRemoved() {
        let m = makeModel()
        m.handle(.prompt(sessionId: "s1", prompt: prompt("i1", state: .pending)))
        m.handle(.prompt(sessionId: "s1", prompt: prompt("i1", state: .cancelled)))
        XCTAssertTrue((m.prompts["s1"] ?? []).isEmpty)
    }

    func testPendingPromptUpdatedInPlace() {
        let m = makeModel()
        m.handle(.prompt(sessionId: "s1", prompt: prompt("i1", state: .pending)))
        m.handle(.prompt(sessionId: "s1", prompt: ChatPrompt(
            itemId: "i1", revision: 1, kind: .approval, title: "t2", detail: nil,
            options: [], state: .pending, selectedOptionId: nil)))
        XCTAssertEqual(m.prompts["s1"]?.count, 1)   // deduped by itemId
        XCTAssertEqual(m.prompts["s1"]?.first?.revision, 1)
    }

    func testDeadActiveSessionClearsPrompts() {
        let m = makeModel()
        m.handle(.prompt(sessionId: "s1", prompt: prompt("i1", state: .pending)))
        m.subscribeChat("s1")   // active session = s1
        m.handle(.sessions([]))  // s1 is no longer live
        XCTAssertNil(m.prompts["s1"])
    }

    func testPromptDraftSurvivesAndIsDroppedOnResolve() {
        let model = makeModel()
        model.handle(.prompt(sessionId: "s1", prompt: pendingPrompt(itemId: "q1")))
        model.updatePromptDraft("s1", itemId: "q1",
                                PromptDraft().toggling(question: 0, option: 1, multiSelect: true))
        XCTAssertEqual(model.promptDraft("s1", itemId: "q1").selections[0], [1])
        model.handle(.prompt(sessionId: "s1", prompt: resolved(pendingPrompt(itemId: "q1"))))
        XCTAssertEqual(model.promptDraft("s1", itemId: "q1"), PromptDraft())
    }
}
