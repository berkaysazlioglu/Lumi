import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiState

/// Tasks planı, Faz 1: `TasksStore` sözleşmesi — bağlama akışı, yalnız
/// görünürken tazeleme, iyimser yazım + geri alma, kaynak durumları.
@MainActor
final class TasksStoreTests: XCTestCase {
    private let me = TaskUser(id: "me", name: "Me")
    private let ada = TaskUser(id: "ada", name: "Ada")

    /// Varsayılan erteleme hiç dolmaz: testler gönderimi `flushAll` ile tetikler.
    static let neverFires: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    private func makeStore(
        _ provider: FakeTaskProvider,
        agents: any TaskAgentRunning = FakeTaskAgentRunner(),
        images: any TaskImageLoading = FakeTaskImageLoader(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in throw CancellationError() },
        debounce: @escaping @Sendable (Duration) async throws -> Void = TasksStoreTests.neverFires
    ) -> (TasksStore, ToastStore) {
        let toasts = ToastStore(autoDismissAfter: 60)
        let factory = FakeTaskProviderFactory(providers: [.demo: provider, .custom: provider])
        let store = TasksStore(
            factory: factory, config: FakeConfigService(), credentials: FakeTaskCredentialStore(),
            images: images, agents: agents, toasts: toasts,
            now: { Date(timeIntervalSince1970: 500) }, sleep: sleep, debounce: debounce
        )
        return (store, toasts)
    }

    /// Demo adapter'ıyla bağlama akışını uçtan uca koşar.
    private func connect(_ store: TasksStore) async {
        store.beginConnect()
        store.selectConnectKind(.demo)
        await store.verifyConnect()
        await store.finishConnect()
    }

    private func connectedStore(
        tasks: [TaskItem],
        info: TaskSourceInfo = .fakeFull(me: TaskUser(id: "me", name: "Me"))
    ) async -> (TasksStore, FakeTaskProvider, ToastStore) {
        let provider = FakeTaskProvider(info: info, tasks: tasks, users: [me, ada])
        let (store, toasts) = makeStore(provider)
        await connect(store)
        return (store, provider, toasts)
    }

    // MARK: - Bağlama

    func testConnectingVerifiesThenLoadsTasksAndDirectories() async {
        let (store, _, toasts) = await connectedStore(tasks: [.fake(id: "1"), .fake(id: "2", status: .done)])

        XCTAssertNil(store.connectFlow, "sheet kapanır")
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources[0].phase, .ready)
        XCTAssertEqual(store.sources[0].source.name, "Fake", "ad yazılmadıysa kaynağın kendi adı")
        XCTAssertEqual(store.sources[0].users.map(\.id), ["me", "ada"])
        XCTAssertEqual(Set(store.entries.map(\.item.id)), ["1", "2"])
        XCTAssertEqual(toasts.toasts.last?.title, "Connected Fake")
    }

    func testFailedVerificationCannotConnect() async {
        let provider = FakeTaskProvider()
        await provider.setDiscoverError(.unauthorized)
        let (store, _) = makeStore(provider)
        store.beginConnect()
        store.selectConnectKind(.demo)
        await store.verifyConnect()

        XCTAssertEqual(store.connectFlow?.canConnect, false)
        await store.finishConnect()
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertNotNil(store.connectFlow, "sheet açık kalır, kullanıcı raporu görür")
    }

    func testCustomSourceRejectsInsecureAddressBeforeAnyRequest() async {
        let provider = FakeTaskProvider()
        let (store, _) = makeStore(provider)
        store.beginConnect()
        store.connectFlow?.address = "http://example.com"
        store.connectFlow?.token = "secret"
        await store.verifyConnect()

        XCTAssertEqual(store.connectFlow?.addressProblem, TaskEndpoint.Problem.insecure.message)
        XCTAssertNil(store.connectFlow?.report)
        let discoverCount = await provider.discoverCount
        XCTAssertEqual(discoverCount, 0)
    }

    func testCustomSourceNeedsAddressAndToken() {
        var flow = TaskConnectFlow(kind: .custom)
        XCTAssertFalse(flow.canVerify)
        flow.address = "https://x.dev"
        XCTAssertFalse(flow.canVerify)
        flow.token = "t"
        XCTAssertTrue(flow.canVerify)
        XCTAssertTrue(TaskConnectFlow(kind: .demo).canVerify)
        XCTAssertFalse(TaskConnectFlow(kind: .github).canVerify, "yazılmamış adapter")
    }

    func testEditingInputsInvalidatesThePreviousReport() async {
        let (store, _) = makeStore(FakeTaskProvider())
        store.beginConnect()
        store.selectConnectKind(.demo)
        await store.verifyConnect()
        XCTAssertNotNil(store.connectFlow?.report)

        store.connectInputsChanged()
        XCTAssertNil(store.connectFlow?.report)
        XCTAssertEqual(store.connectFlow?.canConnect, false)
    }

    // MARK: - Tazeleme (kullanıcı kararı 6)

    func testNoRequestsHappenUnlessTheRouteKeepsItFresh() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        let afterConnect = await provider.listCount

        await provider.setTasks([.fake(id: "1"), .fake(id: "2")])
        try? await Task.sleep(for: .milliseconds(20))
        let idle = await provider.listCount
        XCTAssertEqual(idle, afterConnect, "route kapalıyken istek yok")
        XCTAssertEqual(store.entries.count, 1)

        await store.keepFresh()
        let refreshed = await provider.listCount
        XCTAssertEqual(refreshed, afterConnect + 1, "route açılınca hemen güncel hâl")
        XCTAssertEqual(store.entries.count, 2)
    }

    func testKeepFreshRepeatsUntilCancelled() async {
        let provider = FakeTaskProvider(tasks: [.fake(id: "1")])
        let sleeps = SleepRecorder()
        let (store, _) = makeStore(provider, sleep: { duration in
            try await sleeps.sleep(duration)
        })
        await connect(store)
        let base = await provider.listCount

        let loop = Task { await store.keepFresh() }
        await sleeps.waitForCalls(3)
        loop.cancel()
        await loop.value

        let count = await provider.listCount
        XCTAssertGreaterThanOrEqual(count - base, 3)
        let durations = await sleeps.durations
        XCTAssertTrue(durations.allSatisfy { $0 == TasksStore.refreshInterval })
    }

    func testUnauthorizedRefreshAsksToReconnectAndKeepsTasks() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        await provider.setListError(.unauthorized)
        await store.refreshAll()

        XCTAssertEqual(store.sources[0].phase, .reconnect)
        XCTAssertEqual(store.entries.count, 1, "veri silinmez")
    }

    func testOfflineRefreshKeepsLastList() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        await provider.setListError(.unreachable("timed out"))
        await store.refreshAll()

        guard case .offline(let message) = store.sources[0].phase else { return XCTFail("offline bekleniyordu") }
        XCTAssertTrue(message.contains("timed out"))
        XCTAssertEqual(store.entries.map(\.item.id), ["1"])
        XCTAssertNotNil(store.sources[0].lastUpdated)
    }

    func testRecoveringFromReconnectRunsDiscoveryAgain() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        await provider.setListError(.unauthorized)
        await store.refreshAll()
        await provider.setListError(nil)
        let before = await provider.discoverCount

        await store.refreshAll()
        let after = await provider.discoverCount
        XCTAssertEqual(after, before + 1)
        XCTAssertEqual(store.sources[0].phase, .ready)
    }

    // MARK: - Yazımlar

    func testMoveIsOptimisticAndPersisted() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        let key = store.entries[0].key
        let before = await provider.updates.count
        store.move(key, to: .done)
        XCTAssertEqual(store.entry(key)?.item.status, .done, "ekranda hemen")
        XCTAssertTrue(store.hasPendingWrites)
        await store.flushAll()

        XCTAssertFalse(store.hasPendingWrites)
        XCTAssertEqual(store.entry(key)?.item.status, .done)
        let updates = await provider.updates
        XCTAssertEqual(updates.dropFirst(before).map(\.id), ["1"])
        XCTAssertEqual(updates.last?.patch.status, .done)
    }

    func testFailedMoveRevertsAndShowsToast() async {
        let (store, provider, toasts) = await connectedStore(tasks: [.fake(id: "1")])
        await provider.setUpdateError(.unreachable("down"))
        let key = store.entries[0].key
        store.move(key, to: .done)
        await store.flushAll()

        XCTAssertEqual(store.entry(key)?.item.status, .todo)
        XCTAssertEqual(toasts.toasts.last?.title, "Couldn't save 1")
        XCTAssertEqual(store.failureLog.first?.failure.operation, .update)
        XCTAssertEqual(store.failureLog.first?.failure.taskID, "1")
    }

    func testRefreshDuringInFlightWriteDoesNotClobberIt() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        let key = store.entries[0].key
        await provider.holdUpdates()

        let before = await provider.updates.count
        store.move(key, to: .done)
        let write = Task { await store.flushAll() }
        while await provider.updates.count == before { await Task.yield() }
        XCTAssertEqual(store.entry(key)?.item.status, .done, "iyimser")

        await store.refreshAll()
        XCTAssertEqual(store.entry(key)?.item.status, .done, "sunucunun eski kopyası yazımı ezmez")

        await provider.releaseUpdates()
        await write.value
        await store.refreshAll()
        XCTAssertEqual(store.entry(key)?.item.status, .done)
    }

    func testDeleteRemovesAndUnselects() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1"), .fake(id: "2")])
        let key = store.entries.first { $0.item.id == "1" }!.key
        store.selectedTask = key
        await store.delete(key)

        XCTAssertNil(store.entry(key))
        XCTAssertNil(store.selectedTask)
        let deleted = await provider.deleted
        XCTAssertEqual(deleted.last, "1")
    }

    func testUnsupportedWritesAreNoOps() async {
        let info = TaskSourceInfo(fields: [.assignee: .read, .priority: .read])
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")], info: info)
        let key = store.entries[0].key

        store.assign(key, to: ada)
        store.setPriority(key, to: .high)
        await store.delete(key)
        await store.flushAll()

        let updates = await provider.updates
        let deleted = await provider.deleted
        XCTAssertTrue(updates.isEmpty)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertNotNil(store.entry(key))
    }

    func testAssignOptionsPutYouFirst() async {
        let (store, _, _) = await connectedStore(tasks: [])
        let options = store.assignOptions(for: store.sources[0].id)
        XCTAssertEqual(options.map(\.user.id), ["me", "ada"])
        XCTAssertTrue(options[0].isMe)
    }

    func testMaskedCapabilityHidesCreate() async {
        let (store, _, _) = await connectedStore(tasks: [])
        XCTAssertFalse(store.creatableSources.isEmpty)

        store.setCapability(.create, hidden: true, in: store.sources[0].id)
        XCTAssertTrue(store.creatableSources.isEmpty)
        store.beginNewTask()
        XCTAssertNil(store.newTaskForm)
    }

    // MARK: - Yeni task

    func testSubmittingNewTaskSendsOnlyWritableFields() async {
        let info = TaskSourceInfo(capabilities: [.create], fields: [.priority: .read])
        let (store, provider, _) = await connectedStore(tasks: [], info: info)
        store.beginNewTask(status: .inProgress)
        store.newTaskForm?.title = "  Ship it  "
        store.newTaskForm?.body = "details"
        store.newTaskForm?.priority = .high
        await store.submitNewTask()

        // İlk taslak Verify'ın kendi test task'idir.
        let created = await provider.created
        XCTAssertEqual(created.count, 2)
        let draft = created[1]
        XCTAssertEqual(draft.title, "Ship it")
        XCTAssertEqual(draft.status, .inProgress)
        XCTAssertNil(draft.body, "body beyan edilmedi")
        XCTAssertNil(draft.priority, "priority salt okunur")
        XCTAssertNil(store.newTaskForm)
        XCTAssertEqual(store.selectedTask?.id, "NEW-2")
        XCTAssertEqual(store.entries.map(\.item.id), ["NEW-1", "NEW-2"], "create'siz delete: verify task'i kalır")
    }

    func testRemovingSourceDropsItsTasksAndFilter() async {
        let (store, _, _) = await connectedStore(tasks: [.fake(id: "1")])
        let id = store.sources[0].id
        store.filter.source = id
        store.removeSource(id)

        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.filter.source)
    }

    // MARK: - Birleşik yazım

    func testEditsToOneTaskCoalesceIntoOnePatch() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        let key = store.entries[0].key
        let before = await provider.updates.count
        store.move(key, to: .inProgress)
        store.move(key, to: .inReview)
        store.setPriority(key, to: .urgent)
        store.assign(key, to: ada)
        await store.flushAll()

        let updates = Array(await provider.updates.dropFirst(before))
        XCTAssertEqual(updates.count, 1, "tek PATCH")
        XCTAssertEqual(updates[0].patch, TaskPatch(status: .inReview, priority: .urgent, assignee: .assign(ada)))
        XCTAssertEqual(store.entry(key)?.item.status, .inReview)
    }

    func testDebounceSendsAutomaticallyWhenItElapses() async {
        let provider = FakeTaskProvider(tasks: [.fake(id: "1")])
        let (store, _) = makeStore(provider, debounce: { _ in })
        await connect(store)
        let key = store.entries[0].key
        let before = await provider.updates.count

        store.move(key, to: .done)
        while await provider.updates.count == before { await Task.yield() }
        while store.hasPendingWrites { await Task.yield() }
        let updates = await provider.updates
        XCTAssertEqual(updates.last?.patch.status, .done)
    }

    /// Hata kaydı (2026-10-25): zamanlayıcı süresi dolunca çağrılan `flush`
    /// kendi görevini iptal ediyordu; istek CancellationError ile düşüp task
    /// eski durumuna dönüyordu (Start → In Progress → Todo).
    func testDebouncedWriteIsNotCancelledByItsOwnTimer() async {
        let provider = FakeTaskProvider(tasks: [.fake(id: "1")])
        let (store, _) = makeStore(provider, debounce: { _ in })
        await connect(store)
        let key = store.entries[0].key

        store.move(key, to: .inProgress)
        while store.hasPendingWrites { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(store.entry(key)?.item.status, .inProgress, "sunucu kabul etti, geri dönmemeli")
        XCTAssertTrue(store.failureLog.isEmpty, "\(store.failureLog.map(\.failure.summary))")
        let saved = await provider.tasks.first?.status
        XCTAssertEqual(saved, .inProgress)
    }

    func testCancelledRefreshIsNotAnOutage() async {
        let (store, _, _) = await connectedStore(tasks: [.fake(id: "1")])
        let refresh = Task { await store.refreshAll() }
        refresh.cancel()
        await refresh.value
        XCTAssertEqual(store.sources[0].phase, .ready, "route kapanınca iptal edilen tazeleme kesinti sayılmaz")
        XCTAssertTrue(store.failureLog.isEmpty)
    }

    func testRefreshWhilePendingKeepsLocalEdit() async {
        let (store, _, _) = await connectedStore(tasks: [.fake(id: "1")])
        let key = store.entries[0].key
        store.move(key, to: .done)
        await store.refreshAll()
        XCTAssertEqual(store.entry(key)?.item.status, .done, "gönderilmemiş düzenleme ezilmez")
    }

    func testDeleteDropsPendingEdit() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        let key = store.entries[0].key
        let before = await provider.updates.count
        store.move(key, to: .done)
        await store.delete(key)
        await store.flushAll()
        let after = await provider.updates.count
        XCTAssertEqual(after, before, "silinen task'e PATCH gitmez")
        XCTAssertFalse(store.hasPendingWrites)
    }

    // MARK: - Hata kaydı

    func testRepeatedRefreshFailureIsCountedOnOneLine() async {
        let (store, provider, _) = await connectedStore(tasks: [.fake(id: "1")])
        await provider.setListError(.invalidResponse("not JSON"))
        await store.refreshAll()
        await store.refreshAll()

        guard case .failing = store.sources[0].phase else { return XCTFail("bozuk yanıt offline değil, failing") }
        XCTAssertEqual(store.failureLog.count, 1)
        XCTAssertEqual(store.failureLog[0].count, 2)
        XCTAssertEqual(store.failureLog[0].failure.operation, .listTasks)
        XCTAssertEqual(store.lastFailure(in: store.sources[0].id)?.id, store.failureLog[0].id)
    }

    func testRemovingSourceClearsItsFailures() async {
        let (store, provider, _) = await connectedStore(tasks: [])
        await provider.setListError(.unreachable("down"))
        await store.refreshAll()
        XCTAssertFalse(store.failureLog.isEmpty)
        store.removeSource(store.sources[0].id)
        XCTAssertTrue(store.failureLog.isEmpty)
    }

    func testImageLoadFailureIsRecorded() async {
        let loader = FakeTaskImageLoader()
        await loader.setError(.notFound)
        let provider = FakeTaskProvider()
        let (store, _) = makeStore(provider, images: loader)
        await connect(store)

        let file = await store.imageFile(for: URL(string: "https://x.dev/a.png")!, in: store.sources[0].id, task: "1")
        XCTAssertNil(file)
        XCTAssertEqual(store.failureLog.first?.failure.operation, .loadImage)
    }

    // MARK: - Ajan

    func testStartingAgentMovesToInProgressAssignsAndSubmitsToReview() async {
        let runner = FakeTaskAgentRunner(script: [
            .started(nil), .state(.working), .state(.submitted(summary: "done")),
        ])
        let provider = FakeTaskProvider(info: .fakeFull(me: me), tasks: [.fake(id: "1")], users: [me])
        let (store, _) = makeStore(provider, agents: runner)
        await connect(store)
        let key = store.entries[0].key
        store.beginStart(key)
        XCTAssertEqual(store.startingTask, key)

        let request = TaskAgentRequest(
            task: key, taskTitle: "Task 1", checkout: .existing(path: "/p"), agent: TaskAgentChoice(model: .opus), prompt: "go"
        )
        store.start(request, moveToInProgress: true, assignToMe: true)
        XCTAssertNil(store.startingTask)
        XCTAssertEqual(store.entry(key)?.item.status, .inProgress)
        XCTAssertEqual(store.entry(key)?.item.assignee, me)

        while store.agentLink(for: key)?.state != .submitted(summary: "done") { await Task.yield() }
        while store.hasPendingWrites { await Task.yield() }
        XCTAssertEqual(store.entry(key)?.item.status, .inReview)
        XCTAssertEqual(runner.requests.map(\.prompt), ["go"])
        let last = await provider.updates.last
        XCTAssertEqual(last?.patch.status, .inReview, "teslim beklemeden gönderilir")
    }

    func testStoppingAgentMarksExitedAndDismissRemovesLink() async {
        let (store, _, _) = await connectedStore(tasks: [.fake(id: "1")])
        let key = store.entries[0].key
        store.start(
            TaskAgentRequest(task: key, taskTitle: "t", checkout: .existing(path: "/p"), agent: TaskAgentChoice(), prompt: "p"),
            moveToInProgress: false, assignToMe: false
        )
        store.stopAgent(key)
        XCTAssertEqual(store.agentLink(for: key)?.state, .exited)
        store.beginStart(key)
        XCTAssertEqual(store.startingTask, key, "bitmiş ajan yeniden başlatılabilir")
        store.dismissAgent(key)
        XCTAssertNil(store.agentLink(for: key))
    }

    func testSimulatedFailureIsForwardedOnlyToSimulatingProviders() async {
        let (store, _, _) = await connectedStore(tasks: [])
        let id = store.sources[0].id
        XCTAssertFalse(store.canSimulateFailures(in: id), "fake sağlayıcı taklit etmez")
        store.setSimulatedFailure(.offline, in: id)
        XCTAssertNil(store.sources[0].simulatedFailure)
    }

    // MARK: - Kalıcılık (Faz 2)

    private func persistentStore(
        _ provider: FakeTaskProvider, config: FakeConfigService, credentials: FakeTaskCredentialStore
    ) -> TasksStore {
        TasksStore(
            factory: FakeTaskProviderFactory(providers: [.demo: provider, .custom: provider]),
            config: config, credentials: credentials,
            images: FakeTaskImageLoader(), agents: FakeTaskAgentRunner(), toasts: ToastStore(autoDismissAfter: 60),
            sleep: { _ in throw CancellationError() }, debounce: TasksStoreTests.neverFires
        )
    }

    private func connectCustom(_ store: TasksStore, address: String = "my-app.herokuapp.com", token: String = "tok") async {
        store.beginConnect()
        store.connectFlow?.address = address
        store.connectFlow?.token = token
        await store.verifyConnect()
        await store.finishConnect()
    }

    func testConnectingCustomPersistsRecordAndTokenSeparately() async {
        let config = FakeConfigService()
        let credentials = FakeTaskCredentialStore()
        let store = persistentStore(FakeTaskProvider(), config: config, credentials: credentials)
        await connectCustom(store)

        let saved = await config.config().taskSources
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].kind, .custom)
        XCTAssertEqual(saved[0].baseURL, "https://my-app.herokuapp.com")
        let tokens = await credentials.tokens
        XCTAssertEqual(tokens[saved[0].id], "tok")
        XCTAssertEqual(store.sources.map(\.id), saved.map(\.id))
    }

    func testKeychainWriteFailureKeepsTheSheetOpen() async {
        let config = FakeConfigService()
        let credentials = FakeTaskCredentialStore()
        await credentials.setWriteFails(true)
        let store = persistentStore(FakeTaskProvider(), config: config, credentials: credentials)
        await connectCustom(store)

        XCTAssertNotNil(store.connectFlow)
        XCTAssertTrue(store.sources.isEmpty)
        let saved = await config.config().taskSources
        XCTAssertTrue(saved.isEmpty, "token yazılamadıysa kayıt da yazılmaz")
    }

    func testLoadRestoresSourcesWithoutTouchingTheNetwork() async {
        let custom = TaskSource(id: TaskSourceID("c"), name: "Team", kind: .custom, baseURL: "https://x.dev")
        let demo = TaskSource(id: TaskSourceID("d"), name: "Demo", kind: .demo)
        let config = FakeConfigService()
        var seeded = AppConfig.defaults
        seeded.taskSources = [custom, demo]
        await config.seed(seeded)
        let provider = FakeTaskProvider(tasks: [.fake(id: "1")])
        let store = persistentStore(provider, config: config, credentials: FakeTaskCredentialStore(tokens: [custom.id: "t"]))

        await store.load()
        XCTAssertEqual(store.sources.map(\.source.name), ["Team", "Demo"])
        XCTAssertTrue(store.sources.allSatisfy { $0.phase == .loading })
        let discoverCount = await provider.discoverCount
        XCTAssertEqual(discoverCount, 0, "açılışta istek yok — route açılınca")

        await store.refreshAll()
        XCTAssertTrue(store.sources.allSatisfy { $0.phase == .ready })
    }

    func testMissingTokenAsksToReconnect() async {
        let custom = TaskSource(id: TaskSourceID("c"), name: "Team", kind: .custom, baseURL: "https://x.dev")
        let config = FakeConfigService()
        var seeded = AppConfig.defaults
        seeded.taskSources = [custom]
        await config.seed(seeded)
        let store = persistentStore(FakeTaskProvider(), config: config, credentials: FakeTaskCredentialStore())

        await store.load()
        XCTAssertEqual(store.sources.first?.phase, .reconnect)
        XCTAssertEqual(store.failureLog.first?.failure.serverMessage, "No token in the Keychain for this source")
    }

    func testRemovingCustomSourceDeletesRecordAndToken() async {
        let config = FakeConfigService()
        let credentials = FakeTaskCredentialStore()
        let store = persistentStore(FakeTaskProvider(), config: config, credentials: credentials)
        await connectCustom(store)
        let id = store.sources[0].id

        store.removeSource(id)
        while await !config.config().taskSources.isEmpty { await Task.yield() }
        while await credentials.tokens[id] != nil { await Task.yield() }
    }

    func testReconnectKeepsTheSourceAndReplacesToken() async {
        let config = FakeConfigService()
        let credentials = FakeTaskCredentialStore()
        let provider = FakeTaskProvider(tasks: [.fake(id: "1")])
        let store = persistentStore(provider, config: config, credentials: credentials)
        await connectCustom(store, token: "old")
        let id = store.sources[0].id
        await provider.setListError(.unauthorized)
        await store.refreshAll()
        XCTAssertEqual(store.sources[0].phase, .reconnect)

        await provider.setListError(nil)
        store.beginReconnect(id)
        XCTAssertEqual(store.connectFlow?.address, "https://my-app.herokuapp.com")
        store.connectFlow?.token = "new"
        await store.verifyConnect()
        await store.finishConnect()

        XCTAssertEqual(store.sources.map(\.id), [id], "yeni kaynak eklenmez")
        XCTAssertEqual(store.sources[0].phase, .ready)
        let tokens = await credentials.tokens
        XCTAssertEqual(tokens[id], "new")
        let saved = await config.config().taskSources
        XCTAssertEqual(saved.map(\.id), [id])
    }

    // MARK: - Ajan bağlantısı kalıcılığı (Faz 3)

    private func agentStore(
        _ runner: FakeTaskAgentRunner, config: FakeConfigService, tasks: [TaskItem] = [.fake(id: "1")]
    ) -> (TasksStore, FakeTaskProvider) {
        let provider = FakeTaskProvider(info: .fakeFull(me: me), tasks: tasks)
        let store = TasksStore(
            factory: FakeTaskProviderFactory(providers: [.demo: provider]),
            config: config, credentials: FakeTaskCredentialStore(),
            images: FakeTaskImageLoader(), agents: runner, toasts: ToastStore(autoDismissAfter: 60),
            sleep: { _ in throw CancellationError() }, debounce: TasksStoreTests.neverFires
        )
        return (store, provider)
    }

    private func request(_ key: TaskKey) -> TaskAgentRequest {
        TaskAgentRequest(task: key, taskTitle: "t", checkout: .existing(path: "/repo"), agent: TaskAgentChoice(model: .sonnet), prompt: "p")
    }

    func testStartedAgentIsPersistedWithItsSession() async {
        let terminal = TerminalID()
        let runner = FakeTaskAgentRunner(script: [.started(terminal, sessionID: "s1"), .state(.working)])
        let config = FakeConfigService()
        let (store, _) = agentStore(runner, config: config)
        await connect(store)
        let key = store.entries[0].key

        store.start(request(key), moveToInProgress: false, assignToMe: false)
        while store.agentLink(for: key)?.state != .working { await Task.yield() }
        var saved: [TaskAgentLinkRecord]?
        while saved?.isEmpty != false { saved = await config.uiState().taskLinks; await Task.yield() }

        XCTAssertEqual(saved?.first?.sessionID, "s1")
        XCTAssertEqual(saved?.first?.checkoutPath, "/repo")
        XCTAssertEqual(saved?.first?.model, .sonnet)
        XCTAssertEqual(store.agentLink(for: key)?.terminalID, terminal)
    }

    func testFailedStartShowsToastAndEndsTheLink() async {
        let runner = FakeTaskAgentRunner(script: [.failed("Couldn't create the workspace: exists")])
        let (store, _) = agentStore(runner, config: FakeConfigService())
        await connect(store)
        let key = store.entries[0].key
        store.start(request(key), moveToInProgress: false, assignToMe: false)
        while store.agentLink(for: key)?.state != .exited { await Task.yield() }
        XCTAssertEqual(store.agentLink(for: key)?.state.isActive, false)
    }

    func testSubmittedChipIsNotOverwrittenByLaterTurns() async {
        let runner = FakeTaskAgentRunner(script: [
            .started(TerminalID(), sessionID: "s1"), .state(.submitted(summary: "ok")), .state(.working), .state(.idle),
        ])
        let (store, _) = agentStore(runner, config: FakeConfigService())
        await connect(store)
        let key = store.entries[0].key
        store.start(request(key), moveToInProgress: false, assignToMe: false)
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(store.agentLink(for: key)?.state, .submitted(summary: "ok"))
        XCTAssertEqual(store.entry(key)?.item.status, .inReview)
    }

    func testRestoreReattachesSavedLinksAndDropsMissingOnes() async {
        let config = FakeConfigService()
        let demo = TaskSource(id: TaskSourceID("d"), name: "Demo", kind: .demo)
        var seededConfig = AppConfig.defaults
        seededConfig.taskSources = [demo]
        await config.seed(seededConfig)
        var ui = UIState.defaults
        ui.taskLinks = [
            TaskAgentLinkRecord(source: demo.id, taskID: "1", sessionID: "alive", checkoutPath: "/repo", model: nil, startedAt: Date(timeIntervalSince1970: 1), summary: nil),
        ]
        await config.seed(ui)
        let runner = FakeTaskAgentRunner()
        let terminal = TerminalID()
        runner.reattachScript = [.started(terminal, sessionID: "alive"), .state(.idle)]
        let (store, _) = agentStore(runner, config: config)

        await store.load()
        let key = TaskKey(source: demo.id, id: "1")
        while store.agentLink(for: key)?.state != .idle { await Task.yield() }
        XCTAssertEqual(store.agentLink(for: key)?.isReattached, true)
        XCTAssertEqual(store.agentLink(for: key)?.terminalID, terminal)
        XCTAssertEqual(runner.reattachedSessions, ["alive"])

        // Terminali bulunamayan kayıt düşer.
        runner.reattachScript = []
        let (fresh, _) = agentStore(runner, config: config)
        await fresh.load()
        while fresh.agentLink(for: key) != nil { await Task.yield() }
    }

    // MARK: - Prompt şablonu

    func testPromptTemplateIsPersistedAndAppliedToPrompts() async {
        let config = FakeConfigService()
        let store = persistentStore(FakeTaskProvider(tasks: [.fake(id: "1", title: "Fix")]), config: config, credentials: FakeTaskCredentialStore())
        await connectCustom(store)
        let id = store.sources[0].id
        let key = store.entries[0].key

        store.beginEditingPromptTemplate(id)
        XCTAssertEqual(store.editingPromptTemplate, id)
        store.setPromptTemplate(TaskPromptTemplate(prefix: "PRE", suffix: "POST"), for: id)

        XCTAssertTrue(store.agentPrompt(for: key).hasPrefix("PRE\n\nWork on task 1: Fix\n\nPOST"))
        XCTAssertEqual(store.copyPrompt(for: key), "PRE\n\nWork on task 1: Fix\n\nPOST")
        var saved = await config.config().taskSources.first?.promptTemplate
        while saved?.prefix != "PRE" { await Task.yield(); saved = await config.config().taskSources.first?.promptTemplate }
        XCTAssertEqual(saved?.suffix, "POST")

        // Yeniden bağlanma şablonu korur.
        store.beginReconnect(id)
        store.connectFlow?.token = "new"
        await store.verifyConnect()
        await store.finishConnect()
        XCTAssertEqual(store.sources[0].source.promptTemplate.prefix, "PRE")
    }

    // MARK: - Görseller ajana ve temizlik

    private func imageTask(_ id: String, urls: [String]) -> TaskItem {
        var item = TaskItem.fake(id: id)
        item.images = urls.map { TaskImage(url: URL(string: $0)!, name: ($0 as NSString).lastPathComponent) }
        return item
    }

    func testStartAttachesImagesAndFlushesStatusImmediately() async {
        let runner = FakeTaskAgentRunner()
        let loader = FakeTaskImageLoader()
        let provider = FakeTaskProvider(info: .fakeFull(me: me), tasks: [imageTask("1", urls: ["https://cdn.x/a.png", "https://cdn.x/b.png"])])
        let store = TasksStore(
            factory: FakeTaskProviderFactory(providers: [.demo: provider]), config: FakeConfigService(),
            credentials: FakeTaskCredentialStore(), images: loader, agents: runner, toasts: ToastStore(autoDismissAfter: 60),
            sleep: { _ in throw CancellationError() }, debounce: TasksStoreTests.neverFires
        )
        await connect(store)
        let key = store.entries[0].key
        XCTAssertEqual(store.attachableImageCount(for: key), 2)
        let before = await provider.updates.count

        store.start(
            TaskAgentRequest(task: key, taskTitle: "t", checkout: .existing(path: "/r"), agent: TaskAgentChoice(), prompt: TaskAgentPrompt.make(task: store.entries[0].item, includeBody: false)),
            moveToInProgress: true, assignToMe: false
        )
        while runner.requests.isEmpty { await Task.yield() }
        let sent = runner.requests[0]
        XCTAssertEqual(sent.attachmentDirectory, "/attachments/1")
        XCTAssertTrue(sent.prompt.contains("- /attachments/1/1-a.png\n- /attachments/1/2-b.png"))
        XCTAssertTrue(sent.prompt.hasSuffix("Never mark it done yourself."), "teslim talimatı son söz kalır")

        var updates = await provider.updates.count
        while updates == before { await Task.yield(); updates = await provider.updates.count }
        let last = await provider.updates.last
        XCTAssertEqual(last?.patch.status, .inProgress, "Start'taki durum 2 sn beklemeden gider")
    }

    func testDeletedAndVanishedTasksLoseTheirImagesUnlessShared() async {
        let loader = FakeTaskImageLoader()
        let provider = FakeTaskProvider(tasks: [
            imageTask("1", urls: ["https://cdn.x/only1.png", "https://cdn.x/shared.png"]),
            imageTask("2", urls: ["https://cdn.x/only2.png"]),
            imageTask("3", urls: ["https://cdn.x/shared.png"]),
        ])
        let store = TasksStore(
            factory: FakeTaskProviderFactory(providers: [.demo: provider]), config: FakeConfigService(),
            credentials: FakeTaskCredentialStore(), images: loader, agents: FakeTaskAgentRunner(), toasts: ToastStore(autoDismissAfter: 60),
            sleep: { _ in throw CancellationError() }, debounce: TasksStoreTests.neverFires
        )
        await connect(store)
        let one = store.entries.first { $0.item.id == "1" }!.key

        await store.delete(one)
        var evicted = await loader.evicted
        while evicted.isEmpty { await Task.yield(); evicted = await loader.evicted }
        XCTAssertEqual(evicted.map(\.lastPathComponent), ["only1.png"], "task 3 hâlâ shared.png'yi kullanıyor")
        let removed = await loader.removedAttachments
        XCTAssertEqual(removed.map(\.id), ["1"])

        // Sunucuda kaybolan task (2) de temizlenir.
        await provider.setTasks(await provider.tasks.filter { $0.id != "2" })
        await store.refreshAll()
        while await loader.removedAttachments.count < 2 { await Task.yield() }
        evicted = await loader.evicted
        XCTAssertTrue(evicted.map(\.lastPathComponent).contains("only2.png"))

        store.removeSource(store.sources[0].id)
        while await loader.removedSources.isEmpty { await Task.yield() }
    }
}

/// `keepFresh`'in uykusunu kaydeder; iptal edilene kadar hemen döner ama her
/// çağrıda kooperatif iptali kontrol eder.
private actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        await Task.yield()
        try Task.checkCancellation()
    }

    func waitForCalls(_ count: Int) async {
        while durations.count < count { await Task.yield() }
    }
}
