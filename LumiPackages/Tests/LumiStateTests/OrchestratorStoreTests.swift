import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

@MainActor
final class OrchestratorStoreTests: XCTestCase {
    private func makeStore(
        service: FakeOrchestratorService = FakeOrchestratorService(),
        config: FakeConfigService = FakeConfigService(),
        ids: [String] = ["s-1", "s-2", "s-3"]
    ) -> OrchestratorStore {
        let queue = IDQueue(ids)
        return OrchestratorStore(service: service, config: config, makeSessionID: { queue.next() })
    }

    private func userText(_ id: String, _ text: String) -> ChatMessage {
        ChatMessage(id: id, role: .user, blocks: [.text(text, presentation: nil)], timestampMs: nil, turnId: id)
    }

    private func assistantText(_ id: String, _ text: String) -> ChatMessage {
        ChatMessage(id: id, role: .assistant, blocks: [.text(text, presentation: nil)], timestampMs: nil, turnId: id)
    }

    /// Bir sonraki main-actor turuna kadar bekler (akış tüketicisi işlesin).
    private func drain() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    func testFirstActivationCreatesAndPersistsNewConversation() async {
        let service = FakeOrchestratorService()
        let config = FakeConfigService()
        let store = makeStore(service: service, config: config)

        await store.activate()

        XCTAssertEqual(service.launches, [OrchestratorLaunch(sessionID: "s-1", resume: false)])
        XCTAssertEqual(store.phase, .running)
        let saved = await config.uiState().orchestratorSessionID
        XCTAssertEqual(saved, "s-1")
    }

    func testStoredConversationIsResumedWithHistory() async {
        let service = FakeOrchestratorService()
        service.stubHistory([userText("u0", "eski"), assistantText("a0", "cevap")])
        let config = FakeConfigService()
        var state = UIState.defaults
        state.orchestratorSessionID = "kept"
        await config.seed(state)
        let store = makeStore(service: service, config: config)

        await store.activate()

        XCTAssertEqual(service.launches, [OrchestratorLaunch(sessionID: "kept", resume: true)])
        XCTAssertEqual(store.messages.map(\.id), ["u0", "a0"])
    }

    func testActivateIsIdempotentWhileRunning() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.activate()
        await store.activate()
        XCTAssertEqual(service.launches.count, 1)
    }

    func testSendShowsPendingUntilEchoAndRespondsUntilTurnResult() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.activate()

        await store.send("  merhaba  ")
        XCTAssertEqual(service.sent, ["merhaba"])
        XCTAssertEqual(store.pendingPrompt, "merhaba")
        XCTAssertTrue(store.isResponding)

        var echoed = ChatJournalState()
        echoed.messages = [userText("u1", "merhaba")]
        service.emit(echoed)
        await drain()
        XCTAssertNil(store.pendingPrompt, "yankı gelince bekleyen balon kalkar")
        XCTAssertTrue(store.isResponding, "turn bitmeden cevap bekleniyor")

        var done = echoed
        done.messages.append(assistantText("a1", "selam"))
        done.completedTurns = 1
        service.emit(done)
        await drain()
        XCTAssertFalse(store.isResponding)
        XCTAssertEqual(store.messages.map(\.id), ["u1", "a1"])
    }

    func testSendLaunchesLazilyWhenIdle() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.send("ilk")
        XCTAssertEqual(service.launches.count, 1)
        XCTAssertEqual(service.sent, ["ilk"])
    }

    func testBlankMessageIsIgnored() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.send("   \n ")
        XCTAssertTrue(service.launches.isEmpty)
        XCTAssertTrue(service.sent.isEmpty)
    }

    func testStartFailureSurfacesErrorAndStaysIdle() async {
        let service = FakeOrchestratorService()
        service.stubStartError(.cliNotFound(binary: "claude"))
        let store = makeStore(service: service)

        await store.send("selam")

        XCTAssertEqual(store.phase, .idle)
        XCTAssertNil(store.pendingPrompt)
        XCTAssertEqual(store.errorMessage, LumiError.cliNotFound(binary: "claude").errorDescription)
        XCTAssertTrue(service.sent.isEmpty)
    }

    func testUnexpectedExitWhileRespondingKeepsMessagesAndReportsError() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.activate()
        await store.send("uzun iş")
        var echoed = ChatJournalState()
        echoed.messages = [userText("u1", "uzun iş")]
        service.emit(echoed)
        await drain()

        service.finish()
        await drain()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.messages.map(\.id), ["u1"], "canlı mesajlar geçmişe katlanır")
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isResponding)
    }

    func testStopResponseKeepsConversationAndNextSendResumes() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.activate()
        await store.send("dur")

        await store.stopResponse()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.isResponding)
        XCTAssertNil(store.errorMessage, "kullanıcının kesmesi hata değildir")

        await store.send("devam")
        XCTAssertEqual(service.launches.last, OrchestratorLaunch(sessionID: "s-1", resume: true))
    }

    func testNewConversationUsesFreshIDAndClearsMessages() async {
        let service = FakeOrchestratorService()
        service.stubHistory([userText("u0", "eski")])
        let config = FakeConfigService()
        var state = UIState.defaults
        state.orchestratorSessionID = "old"
        await config.seed(state)
        let store = makeStore(service: service, config: config)
        await store.activate()
        XCTAssertFalse(store.messages.isEmpty)
        service.stubHistory([])

        await store.newConversation()

        XCTAssertEqual(service.launches.last, OrchestratorLaunch(sessionID: "s-1", resume: false))
        XCTAssertTrue(store.messages.isEmpty)
        let saved = await config.uiState().orchestratorSessionID
        XCTAssertEqual(saved, "s-1")
    }

    /// Faz 2: araç yürütücüsü varsa MCP sunucusu ilk süreçte açılır ve uç
    /// sürece verilir; sonraki süreçler aynı sunucuyu kullanır.
    func testControlServerStartsWithFirstLaunchAndEndpointReachesProcess() async {
        let service = FakeOrchestratorService()
        let control = FakeOrchestratorControlServer()
        let store = OrchestratorStore(
            service: service, config: FakeConfigService(),
            control: control, tools: NoTools(), makeSessionID: { "s-1" }
        )

        await store.activate()

        XCTAssertEqual(control.startCount, 1)
        XCTAssertEqual(service.launches.last?.control, FakeOrchestratorControlServer.endpoint)
        await store.shutdown()
        XCTAssertEqual(control.stopCount, 1)
    }

    func testControlServerFailureSurfacesAsStartError() async {
        let service = FakeOrchestratorService()
        let control = FakeOrchestratorControlServer()
        control.stubStartError(.underlying(domain: "LumiMCPServer", message: "port busy"))
        let store = OrchestratorStore(
            service: service, config: FakeConfigService(),
            control: control, tools: NoTools(), makeSessionID: { "s-1" }
        )

        await store.activate()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(service.launches.isEmpty)
    }

    func testShutdownStopsProcess() async {
        let service = FakeOrchestratorService()
        let store = makeStore(service: service)
        await store.activate()
        await store.shutdown()
        XCTAssertEqual(service.stopCount, 1)
        XCTAssertEqual(store.phase, .idle)
    }
}

/// Sıralı, deterministik oturum kimlikleri.
private final class IDQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String]
    init(_ ids: [String]) { self.ids = ids }
    func next() -> String {
        lock.withLock { ids.isEmpty ? UUID().uuidString : ids.removeFirst() }
    }
}

private struct NoTools: OrchestratorToolHandling {
    func call(name: String, arguments: Data) async -> OrchestratorToolResult { .failure("none") }
}
