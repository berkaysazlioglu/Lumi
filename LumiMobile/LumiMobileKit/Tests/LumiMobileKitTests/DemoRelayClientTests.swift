import XCTest
@testable import LumiMobileKit
import LumiWire

/// Drives the real AppModel against the demo relay (no Mac, no relay).
@MainActor
final class DemoRelayClientTests: XCTestCase {

    private func makeStartedModel() async -> AppModel {
        let client = DemoRelayClient(replyDelay: .zero, connectDelay: .zero, streamTick: nil)
        let model = AppModel(client: client, store: DemoSecureStore(), prefs: InMemoryPreferenceStore())
        model.submitSettle = .zero
        await model.start()
        let ready = await eventually { model.connection == .connected && !model.sessions.isEmpty }
        XCTAssertTrue(ready, "demo welcome never arrived")
        return model
    }

    /// Polls until `condition` holds (frames hop through Tasks and the event stream).
    private func eventually(timeout: Duration = .seconds(2),
                            _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private func texts(_ messages: [ChatMessage]) -> [String] {
        messages.flatMap { $0.blocks.compactMap { if case .text(let t, _) = $0 { t } else { nil } } }
    }

    // MARK: Welcome

    func testDemoStoreIsPaired() {
        let model = AppModel(client: DemoRelayClient(), store: DemoSecureStore(), prefs: InMemoryPreferenceStore())
        XCTAssertTrue(model.isPaired)
    }

    func testStartPopulatesProjectsSessionsAndOthers() async {
        let model = await makeStartedModel()
        XCTAssertTrue(model.macOnline)
        XCTAssertEqual(model.sessions.count, 8)
        XCTAssertEqual(model.projectTree.map(\.node.name), ["word-puzzle", "Lumi", "liman", "Collectioner", "notes"])

        let puzzle = model.projectTree[0]
        XCTAssertEqual(puzzle.node.appearance.color, .lime)
        XCTAssertEqual(puzzle.node.appearance.icon, .emoji("🏖️"))
        XCTAssertEqual(puzzle.checkouts.map { $0.agents.count }, [2, 1])
        XCTAssertEqual(model.projectTree[1].node.appearance.rootTitle, "dev")
        XCTAssertEqual(model.projectTree[4].node.appearance, .none)

        XCTAssertEqual(model.otherGroups.map(\.node.label), ["~", "~/Desktop"])
        XCTAssertEqual(model.projectsSnapshot.looseLocations.map(\.label), ["~", "~/wkspaces"])
        XCTAssertEqual(model.projectsSnapshot.display.terminalFontFamily, "")
        XCTAssertFalse(model.projectsSnapshot.addable.isEmpty)

        let activities = Set(model.sessions.map(\.activity))
        XCTAssertTrue(activities.isSuperset(of: [.running, .awaitingDecision, .done, .failed, .idle]))
        XCTAssertTrue(model.sessions.contains { $0.provider == "codex" })
    }

    // MARK: Chat

    func testSubscribeChatYieldsTranscript() async {
        let model = await makeStartedModel()
        model.subscribeChat(DemoIDs.relay)
        let loaded = await eventually { !model.chatMessages(DemoIDs.relay).isEmpty }
        XCTAssertTrue(loaded)
        let messages = model.chatMessages(DemoIDs.relay)
        XCTAssertTrue(messages.contains { $0.blocks.contains { if case .toolCall(name: "Read", _, _) = $0 { true } else { false } } })
        XCTAssertTrue(texts(messages).contains { $0.contains("| Attempt |") })
        // Tool-only messages fold into the owning text turn.
        XCTAssertLessThan(foldChatMessages(messages).count, messages.count)
    }

    func testWorkingSessionHasLiveTurnAndRewardsHasPrompt() async {
        let model = await makeStartedModel()
        model.subscribeChat(DemoIDs.tiles)
        let working = await eventually { model.turnStatus[DemoIDs.tiles]?.working == true }
        XCTAssertTrue(working)

        model.subscribeChat(DemoIDs.rewards)
        let prompted = await eventually { model.prompts[DemoIDs.rewards]?.count == 1 }
        XCTAssertTrue(prompted)
    }

    func testLiveTurnStreamsTextWordByWord() async {
        let client = DemoRelayClient(replyDelay: .zero, connectDelay: .zero, streamTick: .milliseconds(1))
        let model = AppModel(client: client, store: DemoSecureStore(), prefs: InMemoryPreferenceStore())
        await model.start()
        _ = await eventually { model.connection == .connected }
        model.subscribeChat(DemoIDs.tiles)
        let streamed = await eventually {
            model.turnStatus[DemoIDs.tiles]?.streamingText == DemoData.tilesStreaming
        }
        XCTAssertTrue(streamed)
    }

    func testStopInterruptsWorkingTurn() async {
        let model = await makeStartedModel()
        model.subscribeChat(DemoIDs.tiles)
        _ = await eventually { model.turnStatus[DemoIDs.tiles]?.working == true }
        model.requestStop(DemoIDs.tiles)
        let stopped = await eventually {
            model.turnStatus[DemoIDs.tiles]?.working == false && !model.stoppingSessions.contains(DemoIDs.tiles)
        }
        XCTAssertTrue(stopped)
        XCTAssertEqual(model.session(DemoIDs.tiles)?.status, "waiting-seen")
    }

    func testSubmitTextOnChatProducesAssistantReply() async {
        let model = await makeStartedModel()
        model.subscribeChat(DemoIDs.home)
        _ = await eventually { !model.chatMessages(DemoIDs.home).isEmpty }
        model.submitText(DemoIDs.home, "Tidy up my desktop")

        let replied = await eventually {
            self.texts(model.chatMessages(DemoIDs.home)).contains { $0.contains("## Summary") }
                && model.turnStatus[DemoIDs.home]?.working == false
        }
        XCTAssertTrue(replied)
        XCTAssertTrue(texts(model.chatMessages(DemoIDs.home)).contains("Tidy up my desktop"))
        XCTAssertEqual(model.session(DemoIDs.home)?.status, "waiting-seen")
    }

    func testApprovingPromptResolvesAndContinues() async {
        let model = await makeStartedModel()
        model.subscribeChat(DemoIDs.rewards)
        _ = await eventually { model.prompts[DemoIDs.rewards]?.count == 1 }
        model.respondPrompt(DemoIDs.rewards, itemId: DemoIDs.rewardsPromptItem, revision: 1, optionId: "allow")

        let done = await eventually {
            model.prompts[DemoIDs.rewards]?.isEmpty == true
                && model.session(DemoIDs.rewards)?.awaitingDecision == false
                && self.texts(model.chatMessages(DemoIDs.rewards)).contains { $0.contains("date-fns@4") && $0.contains("installed") }
        }
        XCTAssertTrue(done)
    }

    // MARK: Commands

    func testStartChatSessionAppearsInProjectTree() async {
        let model = await makeStartedModel()
        await model.startChatSession(repoPath: DemoPaths.lumi)
        let started = await eventually { model.lastStartedSessionId != nil }
        XCTAssertTrue(started)
        let sid = model.lastStartedSessionId!
        let listed = await eventually {
            model.session(sid) != nil
                && model.projectTree[1].checkouts[0].agents.contains { $0.id == sid }
        }
        XCTAssertTrue(listed)
        XCTAssertTrue(model.isChatSession(sid))
        XCTAssertEqual(model.activeSessionId, sid)
    }

    func testStartChatSessionInLooseFolderCreatesOtherGroup() async {
        let model = await makeStartedModel()
        await model.startChatSession(repoPath: "/Users/demo/Downloads")
        let started = await eventually { model.lastStartedSessionId != nil }
        XCTAssertTrue(started)
        let sid = model.lastStartedSessionId!
        let grouped = await eventually {
            model.otherGroups.contains { $0.node.label == "~/Downloads" && $0.agents.map(\.id) == [sid] }
        }
        XCTAssertTrue(grouped)
    }

    func testNewBranchCreatesWorkspaceCheckout() async {
        let model = await makeStartedModel()
        await model.startChatSession(repoPath: DemoPaths.liman, branchMode: "new", branchName: "feat/tracking")
        let created = await eventually {
            model.projectTree[2].checkouts.contains { $0.node.kind == "workspace" && $0.node.branch == "feat/tracking" }
        }
        XCTAssertTrue(created)
    }

    func testDeleteSessionRemovesIt() async {
        let model = await makeStartedModel()
        await model.deleteSession(sessionId: DemoIDs.liman)
        let removed = await eventually {
            model.session(DemoIDs.liman) == nil
                && model.projectTree[2].checkouts[0].agents.isEmpty
        }
        XCTAssertTrue(removed)
    }

    func testAddProjectMovesAddableIntoProjects() async {
        let model = await makeStartedModel()
        let repo = model.projectsSnapshot.addable[0]
        await model.addProject(path: repo.path)
        let added = await eventually {
            model.projectTree.contains { $0.node.path == repo.path }
                && !model.projectsSnapshot.addable.contains(repo)
        }
        XCTAssertTrue(added)
        XCTAssertNil(model.addProjectError)
    }

    func testListBranches() async {
        let model = await makeStartedModel()
        await model.loadBranches(repoPath: DemoPaths.wordPuzzle)
        let loaded = await eventually { !model.branchesLoading && !model.branchesForRepo.isEmpty }
        XCTAssertTrue(loaded)
    }

    // MARK: Terminal

    func testTerminalSubscribeSendsAnsiScrollback() async {
        let model = await makeStartedModel()
        XCTAssertFalse(model.isChatSession(DemoIDs.shell))
        model.subscribe(DemoIDs.shell)
        var first: TerminalChunk?
        for await chunk in model.terminalStream(DemoIDs.shell) { first = chunk; break }
        XCTAssertEqual(first?.cols, 80)
        XCTAssertEqual(first?.rows, 24)
        let text = String(decoding: first?.bytes ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("git status"))
        XCTAssertTrue(text.contains("\u{1B}[31m"))
    }

    func testStopFinishesEventStream() async {
        let client = DemoRelayClient(replyDelay: .zero, connectDelay: .zero, streamTick: nil)
        let stream = await client.events()
        await client.start(pairing: DemoSecureStore.pairing)
        await client.stop()
        var events: [ClientEvent] = []
        for await event in stream { events.append(event) }
        XCTAssertEqual(events.last, .stateChanged(.disconnected))
    }
}
