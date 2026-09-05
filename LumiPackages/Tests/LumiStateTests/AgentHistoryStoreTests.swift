import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class AgentHistoryStoreTests: XCTestCase {
    private func entry(_ id: String) -> AgentHistoryEntry {
        AgentHistoryEntry(provider: .claude, sessionID: id, title: id, updatedAt: .now, logPath: "/tmp/\(id)")
    }

    func testResultsAreIsolatedPerProject() async {
        let service = FakeAgentHistoryService(result: [entry("a")])
        let store = AgentHistoryStore(service: service)
        await store.refresh("/a")
        await service.setResult([entry("b")])
        await store.refresh("/b")
        XCTAssertEqual(store.entries["/a"]?.map(\.sessionID), ["a"])
        XCTAssertEqual(store.entries["/b"]?.map(\.sessionID), ["b"])
    }

    func testServiceErrorIsSurfaced() async {
        let service = FakeAgentHistoryService()
        await service.setFailure(TestError.failed)
        let store = AgentHistoryStore(service: service)
        await store.refresh("/repo")
        XCTAssertNotNil(store.errors["/repo"])
    }

    func testEvictionPreventsDelayedRefreshRestoringCache() async {
        let service = FakeAgentHistoryService(result: [entry("late")])
        await service.setDelay(.milliseconds(50))
        let store = AgentHistoryStore(service: service)
        let task = Task { await store.refresh("/repo") }
        await Task.yield()
        store.evict("/repo")
        await task.value
        XCTAssertNil(store.entries["/repo"])
    }

    private enum TestError: Error { case failed }
}
