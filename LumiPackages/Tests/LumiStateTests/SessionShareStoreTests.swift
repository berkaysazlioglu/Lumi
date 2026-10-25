import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiState

/// Oturum sunucusu store'u (karar 138): açılışta ağ yok, popup açılışında
/// 5 dakikalık tazeleme kuralı, bağlanma, yükleyen filtresi, yalnız kendi
/// oturumunu silme, içe/dışa aktarma.
@MainActor
final class SessionShareStoreTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private struct Harness {
        let store: SessionShareStore
        let server: FakeSessionSharing
        let factory: FakeSessionSharingFactory
        let credentials: FakeSessionServerCredentialStore
        let config: FakeConfigService
        let transfer: FakeAgentSessionTransferService
        let toasts: ToastStore
        let clock: Clock
    }

    private let me = SharedSessionUploader(id: "u_me", name: "Me")
    private let ada = SharedSessionUploader(id: "u_ada", name: "Ada")

    private func session(_ id: String, by uploader: SharedSessionUploader) -> SharedSession {
        SharedSession(id: id, title: "Session \(id)", project: "API", provider: .claude, uploader: uploader, uploadedAt: Date())
    }

    private func makeHarness(connected: Bool = true) async throws -> Harness {
        let server = FakeSessionSharing(
            info: SessionServerInfo(name: "Team", me: me),
            sessions: [session("1", by: ada), session("2", by: me)]
        )
        let factory = FakeSessionSharingFactory(server: server)
        let credentials = FakeSessionServerCredentialStore()
        let config = FakeConfigService()
        if connected {
            try await config.updateConfig { $0.sessionServer = SessionServer(id: "srv", name: "Team", baseURL: "https://s.example.com") }
            try await credentials.setToken("tok", for: "srv")
        }
        let transfer = FakeAgentSessionTransferService()
        let toasts = ToastStore(autoDismissAfter: 60)
        let history = AgentHistoryStore(service: FakeAgentHistoryService(), transfer: transfer, toasts: toasts)
        let clock = Clock()
        let store = SessionShareStore(
            factory: factory, credentials: credentials, config: config, history: history, toasts: toasts,
            now: { clock.now }, makeID: { "new-id" }
        )
        await store.load()
        return Harness(
            store: store, server: server, factory: factory, credentials: credentials, config: config,
            transfer: transfer, toasts: toasts, clock: clock
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
    }

    // MARK: - Açılış ve tazeleme kuralı

    func testLoadMakesNoRequest() async throws {
        let h = try await makeHarness()
        XCTAssertTrue(h.store.isConnected)
        let listCount = await h.server.listCount
        XCTAssertEqual(listCount, 0)
        XCTAssertEqual(h.factory.made.first?.token, "tok")
    }

    func testOpeningRefreshesOnlyWhenOlderThanFiveMinutes() async throws {
        let h = try await makeHarness()
        h.store.openBrowser()
        await waitUntil { h.store.lastRefreshedAt != nil }
        var listCount = await h.server.listCount
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(h.store.sessions.count, 2)

        h.store.closeBrowser()
        h.clock.now += 4 * 60
        h.store.openBrowser()
        await Task.yield()
        listCount = await h.server.listCount
        XCTAssertEqual(listCount, 1, "fresh list is reused")

        h.clock.now += 2 * 60
        h.store.openBrowser()
        await waitUntil { !h.store.isRefreshing }
        await waitUntil { h.store.lastRefreshedAt == h.clock.now }
        listCount = await h.server.listCount
        XCTAssertEqual(listCount, 2)
    }

    func testOpeningWithoutConnectionShowsConnectForm() async throws {
        let h = try await makeHarness(connected: false)
        h.store.openBrowser()
        XCTAssertTrue(h.store.isBrowserPresented)
        XCTAssertNotNil(h.store.connectForm)
        XCTAssertEqual(h.store.connectForm?.isReconnect, false)
    }

    func testMissingTokenAsksToReconnect() async throws {
        let config = FakeConfigService()
        try await config.updateConfig { $0.sessionServer = SessionServer(id: "srv", name: "Team", baseURL: "https://s.example.com") }
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = SessionShareStore(
            factory: FakeSessionSharingFactory(), credentials: FakeSessionServerCredentialStore(), config: config,
            history: AgentHistoryStore(service: FakeAgentHistoryService(), transfer: FakeAgentSessionTransferService(), toasts: toasts),
            toasts: toasts
        )
        await store.load()
        XCTAssertFalse(store.isConnected)
        store.openBrowser()
        XCTAssertEqual(store.connectForm?.isReconnect, true)
        XCTAssertEqual(store.connectForm?.address, "https://s.example.com")
    }

    // MARK: - Bağlanma

    func testConnectSavesRecordAndTokenAfterDiscoveryAndList() async throws {
        let h = try await makeHarness(connected: false)
        h.store.openBrowser()
        h.store.connectForm?.address = "s.example.com/"
        h.store.connectForm?.token = "  my-token "
        await h.store.connect()

        XCTAssertNil(h.store.connectForm)
        XCTAssertTrue(h.store.isConnected)
        XCTAssertEqual(h.store.info?.me, me)
        XCTAssertEqual(h.store.sessions.count, 2)
        let saved = await h.config.config().sessionServer
        XCTAssertEqual(saved, SessionServer(id: "new-id", name: "Team", baseURL: "https://s.example.com"))
        let token = await h.credentials.token(for: "new-id")
        XCTAssertEqual(token, .found("my-token"))
    }

    func testConnectFailureKeepsFormWithDetail() async throws {
        let h = try await makeHarness(connected: false)
        await h.server.setFailure(SessionShareFailure(kind: .unauthorized, httpStatus: 401))
        h.store.openBrowser()
        h.store.connectForm?.address = "https://s.example.com"
        h.store.connectForm?.token = "bad"
        await h.store.connect()

        XCTAssertEqual(h.store.connectForm?.failure?.kind, .unauthorized)
        XCTAssertEqual(h.store.connectForm?.isVerifying, false)
        let saved = await h.config.config().sessionServer
        XCTAssertNil(saved)
    }

    func testInsecureAddressCannotBeSubmitted() async throws {
        let h = try await makeHarness(connected: false)
        h.store.openBrowser()
        h.store.connectForm?.address = "http://remote.example.com"
        h.store.connectForm?.token = "tok"
        XCTAssertFalse(h.store.canSubmitConnect)
        XCTAssertNotNil(h.store.addressProblem)
    }

    func testDisconnectForgetsRecordAndToken() async throws {
        let h = try await makeHarness()
        await h.store.disconnect()
        XCTAssertFalse(h.store.isConnected)
        let saved = await h.config.config().sessionServer
        XCTAssertNil(saved)
        let token = await h.credentials.token(for: "srv")
        XCTAssertEqual(token, .missing)
    }

    // MARK: - Liste, filtre, silme

    func testUploadersPutMeFirstAndFilterNarrowsList() async throws {
        let h = try await makeHarness()
        await h.store.refresh()
        XCTAssertEqual(h.store.uploaders.map(\.id), ["u_me", "u_ada"])
        h.store.uploaderFilter = "u_ada"
        XCTAssertEqual(h.store.visibleSessions.map(\.id), ["1"])
    }

    func testOnlyOwnSessionsCanBeDeleted() async throws {
        let h = try await makeHarness()
        await h.store.refresh()
        await h.store.deleteSession("1")
        var deleted = await h.server.deleted
        XCTAssertEqual(deleted, [], "someone else's session is never sent")

        await h.store.deleteSession("2")
        deleted = await h.server.deleted
        XCTAssertEqual(deleted, ["2"])
        XCTAssertEqual(h.store.sessions.map(\.id), ["1"])
    }

    // MARK: - İçe / dışa aktarma

    func testImportDownloadsAndInstallsIntoChosenProject() async throws {
        let h = try await makeHarness()
        await h.store.refresh()
        let ok = await h.store.importSession("1", into: "/projects/api")
        XCTAssertTrue(ok)
        let imported = await h.transfer.importedArchives
        XCTAssertEqual(imported.map(\.projectPath), ["/projects/api"])
    }

    func testExportUploadsWithEditedTitleAndProject() async throws {
        let h = try await makeHarness()
        let entry = AgentHistoryEntry(provider: .codex, sessionID: "abc", title: "Original", updatedAt: Date(), logPath: "/tmp/a.jsonl")
        h.store.beginExport(entry, projectName: "Lumi")
        XCTAssertEqual(h.store.exportDraft?.project, "Lumi")
        h.store.exportDraft?.title = "  Better title "
        await h.store.confirmExport()

        XCTAssertNil(h.store.exportDraft)
        let uploads = await h.server.uploads
        XCTAssertEqual(uploads.map(\.title), ["Better title"])
        XCTAssertEqual(uploads.first?.project, "Lumi")
        XCTAssertEqual(uploads.first?.provider, .codex)
        XCTAssertEqual(h.store.sessions.first?.title, "Better title")
    }

    func testExportRespectsServerUploadLimit() async throws {
        let h = try await makeHarness()
        await h.server.setInfo(SessionServerInfo(name: "Team", me: me, maxUploadBytes: 4))
        let entry = AgentHistoryEntry(provider: .claude, sessionID: "abc", title: "T", updatedAt: Date(), logPath: "/tmp/a.jsonl")
        h.store.beginExport(entry, projectName: "Lumi")
        await h.store.confirmExport()

        XCTAssertEqual(h.store.exportDraft?.failure?.kind, .tooLarge)
        let uploads = await h.server.uploads
        XCTAssertTrue(uploads.isEmpty)
    }

    func testExportWithoutConnectionLeadsToSetup() async throws {
        let h = try await makeHarness(connected: false)
        let entry = AgentHistoryEntry(provider: .claude, sessionID: "abc", title: "T", updatedAt: Date(), logPath: "/tmp/a.jsonl")
        h.store.beginExport(entry, projectName: "Lumi")
        h.store.setUpServerFromExport()
        XCTAssertNil(h.store.exportDraft)
        XCTAssertTrue(h.store.isBrowserPresented)
        XCTAssertNotNil(h.store.connectForm)
    }
}
