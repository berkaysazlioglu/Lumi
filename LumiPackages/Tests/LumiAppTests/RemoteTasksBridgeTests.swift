import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest

@testable import LumiAppCore

/// Telefondaki Tasks köprüsü (karar 137 mobil ek): anlık görüntü ve komutlar.
@MainActor
final class RemoteTasksBridgeTests: XCTestCase {
    private let me = TaskUser(id: "me", name: "Me")
    private var runner: FakeTaskAgentRunner!

    private func connected(_ tasks: [TaskItem], info: TaskSourceInfo? = nil) async -> (TasksStore, FakeTaskProvider) {
        let provider = FakeTaskProvider(info: info ?? .fakeFull(me: me), tasks: tasks, users: [me, TaskUser(id: "ada", name: "Ada")])
        runner = FakeTaskAgentRunner()
        let store = TasksStore(
            factory: FakeTaskProviderFactory(providers: [.demo: provider]), config: FakeConfigService(),
            credentials: FakeTaskCredentialStore(), images: FakeTaskImageLoader(), agents: runner,
            toasts: ToastStore(autoDismissAfter: 60), sleep: { _ in throw CancellationError() },
            debounce: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        store.beginConnect()
        store.selectConnectKind(.demo)
        await store.verifyConnect()
        await store.finishConnect()
        return (store, provider)
    }

    private func bridge(_ store: TasksStore, projects: [String] = ["/w/api"], git: Bool = true) -> RemoteTasksBridge {
        RemoteTasksBridge(
            store: store,
            projects: .init(projectPaths: { projects }, isGit: { _ in git }),
            publishDelay: .zero
        )
    }

    private func payload(_ store: TasksStore, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["sourceId": store.sources[0].id.rawValue].merging(extra) { $1 }
    }

    // MARK: - Anlık görüntü

    func testSnapshotCarriesSourcesTasksAndAgent() async {
        var task = TaskItem.fake(id: "1", status: .inProgress, priority: .high, assignee: me, project: TaskProjectRef(key: "api"))
        task.body = "secret body"
        task.images = [TaskImage(url: URL(string: "https://x/a.png")!)]
        let (store, _) = await connected([task])
        store.start(
            TaskAgentRequest(task: store.entries[0].key, taskTitle: "t", checkout: .existing(path: "/w/api"), agent: TaskAgentChoice(model: .opus), prompt: "p"),
            moveToInProgress: false, assignToMe: false
        )
        let snapshot = RemoteTasksSnapshot.payload(store)
        let source = (snapshot["sources"] as? [[String: Any]])?.first
        XCTAssertEqual(source?["phase"] as? String, "ready")
        XCTAssertEqual((source?["me"] as? [String: Any])?["id"] as? String, "me")
        XCTAssertEqual((source?["users"] as? [[String: Any]])?.count, 2)
        let row = (snapshot["tasks"] as? [[String: Any]])?.first
        XCTAssertEqual(row?["status"] as? String, "in_progress")
        XCTAssertEqual(row?["priority"] as? String, "high")
        XCTAssertEqual(row?["imageCount"] as? Int, 1)
        XCTAssertEqual(row?["hasBody"] as? Bool, true)
        XCTAssertNil(row?["body"], "gövde anlık görüntüye girmez")
        XCTAssertEqual((row?["agent"] as? [String: Any])?["title"] as? String, "Claude Opus")
    }

    func testSnapshotDropsOldestDoneTasksToFitTheBudget() async {
        let open = (1...3).map { TaskItem.fake(id: "o\($0)", title: String(repeating: "x", count: 200)) }
        let done = (1...20).map { TaskItem.fake(id: "d\($0)", title: String(repeating: "y", count: 200), status: .done, updatedAt: Date(timeIntervalSince1970: Double($0))) }
        let (store, _) = await connected(open + done)
        let full = try! JSONSerialization.data(withJSONObject: RemoteTasksSnapshot.payload(store)).count
        let trimmed = RemoteTasksSnapshot.payload(store, budget: full - 1500)
        let ids = (trimmed["tasks"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        let dropped = trimmed["truncatedDone"] as? Int ?? 0
        XCTAssertGreaterThan(dropped, 0)
        XCTAssertTrue(["o1", "o2", "o3"].allSatisfy(ids.contains), "açık task'ler kırpılmaz")
        XCTAssertFalse(ids.contains("d1"), "en eski Done önce gider")
        XCTAssertTrue(ids.contains("d20"))
    }

    func testPublishesOnChange() async {
        let (store, _) = await connected([.fake(id: "1")])
        let box = PublishBox()
        let bridge = bridge(store)
        bridge.start { await box.add($0) }
        while await box.count < 1 { await Task.yield() }
        store.move(store.entries[0].key, to: .done)
        while await box.count < 2 { await Task.yield() }
        let last = await box.last
        let json = try! JSONSerialization.jsonObject(with: last!) as! [String: Any]
        XCTAssertEqual((json["tasks"] as? [[String: Any]])?.first?["status"] as? String, "done")
        bridge.stop()
    }

    // MARK: - Komutlar

    func testMoveAssignDetailAndSubscribe() async {
        var task = TaskItem.fake(id: "1")
        task.body = "the body"
        let (store, _) = await connected([task])
        let bridge = bridge(store)
        let key = store.entries[0].key

        let moved = await bridge.handleTaskCommand(action: "task_move", payload: payload(store, ["taskId": "1", "status": "in_review"]))
        XCTAssertTrue(moved.ok)
        XCTAssertEqual(store.entry(key)?.item.status, .inReview)

        let assigned = await bridge.handleTaskCommand(action: "task_assign", payload: payload(store, ["taskId": "1", "userId": "ada"]))
        XCTAssertTrue(assigned.ok)
        XCTAssertEqual(store.entry(key)?.item.assignee?.id, "ada")
        let unknown = await bridge.handleTaskCommand(action: "task_assign", payload: payload(store, ["taskId": "1", "userId": "zed"]))
        XCTAssertEqual(unknown.error, "unknown_user")

        let detail = await bridge.handleTaskCommand(action: "task_detail", payload: payload(store, ["taskId": "1"]))
        XCTAssertEqual(detail.data?["body"], "the body")
        XCTAssertTrue(detail.data?["prompt"]?.contains("Work on task 1") == true)

        _ = await bridge.handleTaskCommand(action: "tasks_subscribe", payload: [:])
        XCTAssertTrue(store.hasRemoteViewer)
        _ = await bridge.handleTaskCommand(action: "tasks_unsubscribe", payload: [:])
        XCTAssertFalse(store.hasRemoteViewer)

        let invalid = await bridge.handleTaskCommand(action: "task_move", payload: payload(store, ["taskId": "1", "status": "blocked"]))
        XCTAssertEqual(invalid.error, "invalid_status")
        let missing = await bridge.handleTaskCommand(action: "task_move", payload: payload(store, ["taskId": "nope", "status": "done"]))
        XCTAssertEqual(missing.error, "task_not_found")
    }

    func testStartMatchesProjectAndUsesNewWorkspaceOnGit() async {
        let (store, _) = await connected([.fake(id: "1", title: "Fix login", project: TaskProjectRef(key: "api"))])
        let bridge = bridge(store)

        let started = await bridge.handleTaskCommand(action: "task_start", payload: payload(store, ["taskId": "1", "model": "sonnet"]))
        XCTAssertTrue(started.ok, started.error ?? "")
        XCTAssertEqual(started.data?["projectPath"], "/w/api")
        while runner.requests.isEmpty { await Task.yield() }
        let request = runner.requests[0]
        XCTAssertEqual(request.checkout, .newWorkspace(projectPath: "/w/api", branch: "task/1-fix-login"))
        XCTAssertEqual(request.agent.model, .sonnet)
        XCTAssertTrue(request.prompt.contains("Work on task 1: Fix login"))
        XCTAssertEqual(store.entry(store.entries[0].key)?.item.status, .inProgress)
        XCTAssertEqual(store.entry(store.entries[0].key)?.item.assignee?.id, "me")

        let again = await bridge.handleTaskCommand(action: "task_start", payload: payload(store, ["taskId": "1"]))
        XCTAssertFalse(again.ok, "aynı task'e ikinci ajan yok")
    }

    func testStartWithoutMatchAsksForProjectAndRespectsExplicitChoice() async {
        let (store, _) = await connected([.fake(id: "1", project: TaskProjectRef(key: "elsewhere"))])
        let bridge = bridge(store, projects: ["/w/api", "/w/web"], git: false)

        let unmatched = await bridge.handleTaskCommand(action: "task_start", payload: payload(store, ["taskId": "1"]))
        XCTAssertEqual(unmatched.error, "no_project")

        let chosen = await bridge.handleTaskCommand(action: "task_start", payload: payload(store, ["taskId": "1", "projectPath": "/w/web"]))
        XCTAssertTrue(chosen.ok)
        while runner.requests.isEmpty { await Task.yield() }
        XCTAssertEqual(runner.requests[0].checkout, .existing(path: "/w/web"), "git olmayan projede mevcut checkout")
    }

    func testCreateFromPhone() async {
        let (store, _) = await connected([])
        let bridge = bridge(store)
        let created = await bridge.handleTaskCommand(action: "task_create", payload: payload(store, ["title": " New one ", "status": "todo"]))
        XCTAssertTrue(created.ok)
        XCTAssertEqual(store.entries.last?.item.title, "New one")
        let empty = await bridge.handleTaskCommand(action: "task_create", payload: payload(store, ["title": "  "]))
        XCTAssertEqual(empty.error, "missing_title")
    }
}

private actor PublishBox {
    private var items: [Data] = []
    var count: Int { items.count }
    var last: Data? { items.last }
    func add(_ data: Data) { items.append(data) }
}
