import XCTest
@testable import LumiMobileKit
import LumiWire

/// Tasks on the phone (Mac decision 137, mobile addendum): wire format,
/// list shaping, optimistic edits, the viewer lease and the demo board.
@MainActor
final class TasksTests: XCTestCase {
    private func decode(_ json: String) -> ServerMessage? {
        PhoneProtocol.decodeServerMessage(json)
    }

    private func makeModel() -> (AppModel, FakeRelayClient) {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        return (AppModel(client: client, store: store), client)
    }

    private func eventually(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private let snapshotJSON = """
    {"v":1,"type":"tasks","payload":{"generatedAt":1000,"truncatedDone":2,
     "sources":[{"id":"s","name":"Team","kind":"custom","phase":"ready","canAssign":true,
       "capabilities":["create"],"fields":{"priority":"rw"},"me":{"id":"me","name":"Me"},
       "users":[{"id":"me","name":"Me"},{"id":"z","name":"Zed"},{"id":"a","name":"Amy"}]}],
     "tasks":[
       {"source":"s","id":"1","title":"Fix","status":"in_progress","priority":"high","labels":["x"],
        "assignee":{"id":"me","name":"Me"},"updatedAt":5,"needsAttention":false,"imageCount":2,"hasBody":true,
        "agent":{"state":"needsInput","title":"Claude Opus","terminalId":"T-1"}},
       {"source":"s","id":"2","title":"Weird","status":"blocked"},
       {"broken":true}
     ]}}
    """

    // MARK: - Wire

    func testSnapshotDecodesTolerantly() {
        guard case .tasks(let snapshot)? = decode(snapshotJSON) else { return XCTFail("not decoded") }
        XCTAssertEqual(snapshot.truncatedDone, 2)
        XCTAssertEqual(snapshot.sources.first?.assignOptions.map(\.id), ["me", "a", "z"], "You first, then by name")
        XCTAssertTrue(snapshot.sources.first?.canCreate == true)
        XCTAssertEqual(snapshot.tasks.map(\.id), ["1", "2"], "broken row dropped, not the board")
        XCTAssertEqual(snapshot.tasks[0].agent?.state, .needsInput)
        XCTAssertEqual(snapshot.tasks[0].agent?.terminalId, "T-1")
        XCTAssertEqual(snapshot.tasks[1].status, .todo, "unknown status falls back to Todo")
    }

    func testCommandFramesCarryTheTask() throws {
        func payload(_ action: CommandAction) throws -> [String: Any] {
            let frame = PhoneProtocol.commandFrame(OutgoingCommand(commandId: "c", action: action))
            let object = try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any]
            return try XCTUnwrap(object?["payload"] as? [String: Any])
        }
        let move = try payload(.taskMove(source: "s", taskId: "1", status: .inReview))
        XCTAssertEqual(move["action"] as? String, "task_move")
        XCTAssertEqual(move["status"] as? String, "in_review")
        XCTAssertEqual(move["sourceId"] as? String, "s")
        let unassign = try payload(.taskAssign(source: "s", taskId: "1", userId: nil))
        XCTAssertTrue(unassign["userId"] is NSNull)
        let start = try payload(.taskStart(source: "s", taskId: "1", model: .opus, projectPath: nil, existingCheckout: false))
        XCTAssertEqual(start["model"] as? String, "opus")
        XCTAssertEqual(start["checkout"] as? String, "new")
        XCTAssertNil(start["projectPath"])
        XCTAssertEqual(try payload(.tasksSubscribe)["action"] as? String, "tasks_subscribe")
    }

    func testWelcomeCarriesCachedTasks() {
        let json = #"{"v":1,"type":"welcome","payload":{"macOnline":false,"tasks":{"sources":[],"tasks":[{"source":"s","id":"1","title":"T","status":"done"}]}}}"#
        guard case .welcome(let welcome)? = decode(json) else { return XCTFail("not decoded") }
        XCTAssertEqual(welcome.tasks?.tasks.first?.status, .done)
    }

    // MARK: - List shaping

    func testSectionsFilterByStatusSourceAndMine() {
        let me = TaskUserRef(id: "me", name: "Me")
        let tasks = [
            RemoteTask(source: "s", id: "a", title: "A", status: .todo, priority: "low", updatedAt: 9),
            RemoteTask(source: "s", id: "b", title: "B", status: .todo, priority: "urgent", updatedAt: 1),
            RemoteTask(source: "s", id: "c", title: "C", status: .done, assignee: me),
            RemoteTask(source: "t", id: "d", title: "D", status: .inReview, assignee: me),
        ]
        let open: Set<RemoteTaskStatus> = [.todo, .inProgress, .inReview]
        let sections = TaskList.sections(tasks, source: nil, statuses: open, mineOnly: false) { _ in "me" }
        XCTAssertEqual(sections.map(\.status), [.todo, .inReview])
        XCTAssertEqual(sections[0].tasks.map(\.id), ["b", "a"], "urgent before low")
        XCTAssertEqual(TaskList.sections(tasks, source: "t", statuses: open, mineOnly: false) { _ in nil }.flatMap(\.tasks).map(\.id), ["d"])
        XCTAssertEqual(TaskList.sections(tasks, source: nil, statuses: Set(RemoteTaskStatus.allCases), mineOnly: true) { _ in "me" }.flatMap(\.tasks).map(\.id), ["d", "c"], "board order: In Review before Done")
    }

    // MARK: - Model

    func testOptimisticMoveRevertsOnRejection() async {
        let (model, client) = makeModel()
        await model.start()
        guard case .tasks(let snapshot)? = decode(snapshotJSON) else { return XCTFail() }
        model.handle(.tasks(snapshot))
        let ref = TaskRef(source: "s", id: "1")

        model.moveTask(ref, to: .done)
        XCTAssertEqual(model.task(ref)?.status, .done, "shown at once")
        let sent = await eventually { client.commands.contains { if case .taskMove = $0.action { true } else { false } } }
        XCTAssertTrue(sent)
        let command = client.commands.last!
        model.handle(.commandResult(CommandResult(commandId: command.commandId, ok: false, error: "validation failed")))
        XCTAssertEqual(model.task(ref)?.status, .inProgress, "Mac's status comes back")
        XCTAssertEqual(model.taskError, "validation failed")
    }

    func testOptimisticEditEndsWhenTheMacAgrees() async {
        let (model, client) = makeModel()
        await model.start()
        guard case .tasks(let snapshot)? = decode(snapshotJSON) else { return XCTFail() }
        model.handle(.tasks(snapshot))
        let ref = TaskRef(source: "s", id: "1")
        model.assignTask(ref, to: TaskUserRef(id: "z", name: "Zed"))
        XCTAssertEqual(model.task(ref)?.assignee?.id, "z")
        _ = await eventually { !client.commands.isEmpty }
        model.handle(.commandResult(CommandResult(commandId: client.commands.last!.commandId, ok: true, error: nil)))
        // Until the Mac's snapshot shows it, the optimistic value stays.
        XCTAssertEqual(model.task(ref)?.assignee?.id, "z")
    }

    func testViewerLeaseSubscribesRenewsAndReleases() async {
        let (model, client) = makeModel()
        model.tasksRenewInterval = .milliseconds(20)
        await model.start()
        model.setTasksVisible(true)
        let renewed = await eventually {
            client.commands.filter { $0.action == .tasksSubscribe }.count >= 2
        }
        XCTAssertTrue(renewed, "lease renewed while visible")
        model.setTasksVisible(false)
        let released = await eventually { client.commands.last?.action == .tasksUnsubscribe }
        XCTAssertTrue(released)
        let count = client.commands.filter { $0.action == .tasksSubscribe }.count
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(client.commands.filter { $0.action == .tasksSubscribe }.count, count, "no renewals after leaving")
    }

    func testStartWithoutProjectAsksToPickOne() async {
        let (model, client) = makeModel()
        await model.start()
        model.startTask(TaskRef(source: "s", id: "1"), model: nil, projectPath: nil, existingCheckout: false)
        XCTAssertEqual(model.taskStartState, .sending)
        _ = await eventually { !client.commands.isEmpty }
        model.handle(.commandResult(CommandResult(commandId: client.commands.last!.commandId, ok: false, error: "no_project")))
        guard case .failed(_, let needsProject) = model.taskStartState else { return XCTFail("\(model.taskStartState)") }
        XCTAssertTrue(needsProject)
    }

    func testDetailIsStoredFromTheResult() async {
        let (model, client) = makeModel()
        await model.start()
        let ref = TaskRef(source: "s", id: "1")
        model.loadTaskDetail(ref)
        _ = await eventually { !client.commands.isEmpty }
        model.handle(.commandResult(CommandResult(commandId: client.commands.last!.commandId, ok: true, error: nil, data: ["body": "Hello", "prompt": "Work"])))
        XCTAssertEqual(model.detail(for: ref), TaskDetail(body: "Hello", prompt: "Work"))
    }

    // MARK: - Demo

    func testDemoBoardRoundTrip() async {
        let client = DemoRelayClient(replyDelay: .zero, connectDelay: .zero, streamTick: nil)
        let model = AppModel(client: client, store: DemoSecureStore(), prefs: InMemoryPreferenceStore())
        await model.start()
        let ready = await eventually { model.tasksSnapshot?.tasks.isEmpty == false }
        XCTAssertTrue(ready)
        let ref = TaskRef(source: DemoTaskBoard.sourceID, id: "WP-14")

        model.startTask(ref, model: .opus, projectPath: nil, existingCheckout: false)
        let started = await eventually { model.taskStartState == .succeeded && model.task(ref)?.agent?.state == .working }
        XCTAssertTrue(started)
        XCTAssertEqual(model.task(ref)?.status, .inProgress)
        XCTAssertEqual(model.task(ref)?.agent?.terminalId, DemoIDs.tiles, "Open Chat lands in a live demo session")

        model.loadTaskDetail(ref)
        let loaded = await eventually { model.detail(for: ref)?.body?.contains("TileDropAnimator") == true }
        XCTAssertTrue(loaded)

        model.createTask(source: DemoTaskBoard.sourceID, title: "From the phone")
        let created = await eventually { model.displayedTasks.contains { $0.title == "From the phone" } }
        XCTAssertTrue(created)
    }
}
