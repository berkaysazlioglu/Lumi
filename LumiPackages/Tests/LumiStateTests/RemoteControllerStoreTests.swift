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
    func sendInput(hubId: String, sessionId: String, data: Data) {}
    func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind) async throws -> String? {
        if let startError { throw startError }
        return nextSessionId
    }
    func closeSession(hubId: String, sessionId: String) async throws {}
    func events() -> AsyncStream<RemoteControllerEvent> { broadcaster.stream() }
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

    @Test func rejectionReasonsReadAsSentences() {
        #expect(RemoteControllerStore.describeRejection("wrong_password") == "Wrong password.")
        #expect(RemoteControllerStore.describeRejection("weird").contains("weird"))
    }
}
