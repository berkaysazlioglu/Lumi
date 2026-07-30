import LumiKit
import XCTest
@testable import LumiState

@MainActor
private final class FakeRemoteDashboardServer: RemoteDashboardServing {
    var status: RemoteDashboardStatus = .stopped
    var startError: LumiError?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func start() async throws {
        startCalls += 1
        if let startError { throw startError }
        status = RemoteDashboardStatus(isRunning: true, url: "http://192.168.1.5:8484")
    }

    func stop() async {
        stopCalls += 1
        status = .stopped
    }
}

@MainActor
final class RemoteDashboardStoreTests: XCTestCase {
    private func waitUntilIdle(_ store: RemoteDashboardStore) async {
        for _ in 0..<100 where store.isBusy {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testToggleStartsServerAndPublishesURL() async {
        let server = FakeRemoteDashboardServer()
        let store = RemoteDashboardStore(server: server, toasts: ToastStore())

        store.toggle()
        XCTAssertTrue(store.isBusy)
        await waitUntilIdle(store)

        XCTAssertTrue(store.isRunning)
        XCTAssertEqual(store.url, "http://192.168.1.5:8484")
        XCTAssertEqual(server.startCalls, 1)
    }

    func testToggleWhileRunningStopsServer() async {
        let server = FakeRemoteDashboardServer()
        let store = RemoteDashboardStore(server: server, toasts: ToastStore())
        store.toggle()
        await waitUntilIdle(store)

        store.toggle()
        await waitUntilIdle(store)

        XCTAssertFalse(store.isRunning)
        XCTAssertNil(store.url)
        XCTAssertEqual(server.stopCalls, 1)
    }

    func testStartFailureSurfacesToast() async {
        let server = FakeRemoteDashboardServer()
        server.startError = .remoteDashboardFailed(detail: "port kullanımda")
        let toasts = ToastStore()
        let store = RemoteDashboardStore(server: server, toasts: toasts)

        store.toggle()
        await waitUntilIdle(store)

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    func testToggleIgnoredWhileBusy() async {
        let server = FakeRemoteDashboardServer()
        let store = RemoteDashboardStore(server: server, toasts: ToastStore())

        store.toggle()
        store.toggle() // busy'ken yut
        await waitUntilIdle(store)

        XCTAssertEqual(server.startCalls, 1)
    }

    func testShutdownStopsServer() async {
        let server = FakeRemoteDashboardServer()
        let store = RemoteDashboardStore(server: server, toasts: ToastStore())
        store.toggle()
        await waitUntilIdle(store)

        await store.shutdown()

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(server.stopCalls, 1)
    }
}
