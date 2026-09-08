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
        let store = AgentHistoryStore(service: service, transfer: FakeAgentSessionTransferService(), toasts: ToastStore())
        await store.refresh("/a")
        await service.setResult([entry("b")])
        await store.refresh("/b")
        XCTAssertEqual(store.entries["/a"]?.map(\.sessionID), ["a"])
        XCTAssertEqual(store.entries["/b"]?.map(\.sessionID), ["b"])
    }

    func testServiceErrorIsSurfaced() async {
        let service = FakeAgentHistoryService()
        await service.setFailure(TestError.failed)
        let store = AgentHistoryStore(service: service, transfer: FakeAgentSessionTransferService(), toasts: ToastStore())
        await store.refresh("/repo")
        XCTAssertNotNil(store.errors["/repo"])
    }

    func testEvictionPreventsDelayedRefreshRestoringCache() async {
        let service = FakeAgentHistoryService(result: [entry("late")])
        await service.setDelay(.milliseconds(50))
        let store = AgentHistoryStore(service: service, transfer: FakeAgentSessionTransferService(), toasts: ToastStore())
        let task = Task { await store.refresh("/repo") }
        await Task.yield()
        store.evict("/repo")
        await task.value
        XCTAssertNil(store.entries["/repo"])
    }

    private enum TestError: Error { case failed }
}

@MainActor
final class AgentHistoryStoreTransferTests: XCTestCase {
    private func entry(_ id: String) -> AgentHistoryEntry {
        AgentHistoryEntry(provider: .claude, sessionID: id, title: id, updatedAt: .now, logPath: "/tmp/\(id)")
    }

    func testExportSuccessShowsSuccessToast() async {
        let transfer = FakeAgentSessionTransferService()
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = AgentHistoryStore(service: FakeAgentHistoryService(), transfer: transfer, toasts: toasts)
        let ok = await store.exportSession(entry("a"), to: URL(fileURLWithPath: "/tmp/a.lumisession.json"))
        XCTAssertTrue(ok)
        XCTAssertEqual(toasts.toasts.map(\.kind), [.success])
        let exported = await transfer.exported
        XCTAssertEqual(exported.map(\.destination.lastPathComponent), ["a.lumisession.json"])
        XCTAssertFalse(store.isTransferring)
    }

    func testExportFailureShowsErrorToast() async {
        let transfer = FakeAgentSessionTransferService()
        await transfer.setFailure(LumiError.sessionTransferFailed(detail: "disk full"))
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = AgentHistoryStore(service: FakeAgentHistoryService(), transfer: transfer, toasts: toasts)
        let ok = await store.exportSession(entry("a"), to: URL(fileURLWithPath: "/tmp/a.json"))
        XCTAssertFalse(ok)
        XCTAssertEqual(toasts.toasts.map(\.kind), [.error])
        XCTAssertTrue(toasts.toasts.first?.message.contains("disk full") ?? false)
    }

    func testImportRefreshesProjectAndReportsRename() async {
        let history = FakeAgentHistoryService(result: [entry("imported")])
        let transfer = FakeAgentSessionTransferService(importResult: AgentSessionImportResult(
            provider: .claude, sessionID: "new", logPath: "/tmp/new.jsonl", subagentCount: 2, didRenameSession: true
        ))
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = AgentHistoryStore(service: history, transfer: transfer, toasts: toasts)
        let result = await store.importSession(from: URL(fileURLWithPath: "/tmp/x.json"), projectPath: "/repo")
        XCTAssertEqual(result?.sessionID, "new")
        XCTAssertEqual(store.entries["/repo"]?.map(\.sessionID), ["imported"])
        XCTAssertEqual(toasts.toasts.map(\.kind), [.success])
        XCTAssertTrue(toasts.toasts.first?.message.contains("2 subagent") ?? false)
        XCTAssertTrue(toasts.toasts.first?.message.contains("renamed") ?? false)
        let imported = await transfer.imported
        XCTAssertEqual(imported.map(\.projectPath), ["/repo"])
    }

    func testImportFailureLeavesEntriesUntouched() async {
        let transfer = FakeAgentSessionTransferService()
        await transfer.setFailure(LumiError.sessionTransferFailed(detail: "bad file"))
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = AgentHistoryStore(service: FakeAgentHistoryService(), transfer: transfer, toasts: toasts)
        let result = await store.importSession(from: URL(fileURLWithPath: "/tmp/x.json"), projectPath: "/repo")
        XCTAssertNil(result)
        XCTAssertNil(store.entries["/repo"])
        XCTAssertEqual(toasts.toasts.map(\.kind), [.error])
    }
}
