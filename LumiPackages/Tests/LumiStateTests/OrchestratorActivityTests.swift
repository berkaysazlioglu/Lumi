import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 114 Faz 4: Activity akışı, model bağlam notu ve özet koordinatörü.
@MainActor
final class OrchestratorActivityFeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func event(_ terminal: TerminalID, _ summary: String, needsUser: Bool = false) -> OrchestratorEvent {
        OrchestratorEvent(terminalID: terminal, terminalTitle: "api", location: "api · main",
                          kind: .finished, summary: summary, needsUser: needsUser, at: now.addingTimeInterval(-120))
    }

    func testNewestFirstOneCardPerTerminalAndUnreadCount() {
        let feed = OrchestratorActivityFeed()
        let a = TerminalID(), b = TerminalID()
        feed.append(event(a, "ilk"))
        feed.append(event(b, "b"))
        feed.append(event(a, "ikinci"))

        XCTAssertEqual(feed.events.map(\.summary), ["ikinci", "b"])
        XCTAssertEqual(feed.unreadCount, 3)
        feed.markAllRead()
        XCTAssertEqual(feed.unreadCount, 0)
    }

    func testContextNoteIsConsumedOnceAndKeepsLatestPerTerminal() throws {
        let feed = OrchestratorActivityFeed()
        let a = TerminalID()
        feed.append(event(a, "eski"))
        feed.append(event(a, "commit atayım mı?", needsUser: true))

        let note = try XCTUnwrap(feed.consumeContextNote(now: now))
        XCTAssertTrue(note.hasPrefix(OrchestratorActivityNote.open))
        XCTAssertTrue(note.hasSuffix(OrchestratorActivityNote.close))
        XCTAssertTrue(note.contains("[finished, asks the user] \"api\" (api · main, id \(a)), 2m ago: commit atayım mı?"))
        XCTAssertFalse(note.contains("eski"))
        XCTAssertNil(feed.consumeContextNote(now: now), "her olay modele bir kez gider")
        XCTAssertEqual(feed.events.count, 1, "not tüketmek paneli boşaltmaz")
    }

    func testStripRemovesOnlyTheLeadingNote() {
        let message = OrchestratorActivityNote.attach("<lumi-activity>\nx\n</lumi-activity>", to: "selam")
        XCTAssertEqual(OrchestratorActivityNote.strip(message), "selam")
        XCTAssertEqual(OrchestratorActivityNote.strip("düz mesaj"), "düz mesaj")
        XCTAssertEqual(OrchestratorActivityNote.attach(nil, to: "selam"), "selam")
    }

    func testCapacityIsBounded() {
        let feed = OrchestratorActivityFeed()
        for index in 0 ..< OrchestratorActivityFeed.capacity + 5 {
            feed.append(event(TerminalID(), "\(index)"))
        }
        XCTAssertEqual(feed.events.count, OrchestratorActivityFeed.capacity)
        XCTAssertEqual(feed.events.first?.summary, "\(OrchestratorActivityFeed.capacity + 4)")
    }
}

@MainActor
final class TerminalDigestCoordinatorTests: XCTestCase {
    private var terminals: TerminalListStore!
    private var transcripts: FakeTerminalTranscripts!
    private var summarizer: FakeTerminalDigestSummarizer!
    private var feed: OrchestratorActivityFeed!
    private var watchList: OrchestratorWatchList!
    private var enabled = true
    private var coordinator: TerminalDigestCoordinator!

    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)

    override func setUp() async throws {
        let toasts = ToastStore(autoDismissAfter: 60)
        let service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: toasts)
        let repos = RepoStore(service: FakeRepoService(repos: [api]))
        await repos.reload()
        let workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(), repos: repos, toasts: toasts
        )
        workspaces.updateSidebarProjects([api.path])
        transcripts = FakeTerminalTranscripts()
        summarizer = FakeTerminalDigestSummarizer()
        feed = OrchestratorActivityFeed()
        watchList = OrchestratorWatchList()
        enabled = true
        self.service = service
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos,
            transcripts: transcripts, screenText: { _ in "" }
        )
        setUpCoordinator()
    }

    private var service: FakeTerminalService!
    private var toolbox: OrchestratorToolbox!

    private func setUpCoordinator() {
        coordinator = TerminalDigestCoordinator(
            service: service, terminals: terminals, toolbox: toolbox, summarizer: summarizer, feed: feed,
            watchList: watchList, isEnabled: { [unowned self] in self.enabled }, settleDelay: .milliseconds(20)
        )
    }

    private func agent(
        provider: AgentProvider? = .claude, session: String? = "s-1", watched: Bool = true
    ) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: "refactor", repoPath: api.path, createdAt: Date(),
                                status: .working, claudeSessionID: session, provider: provider)
        terminals.apply(.spawned(meta))
        coordinator.apply(.spawned(meta))
        if watched { watchList.watch(meta) }
        coordinator.apply(.statusChanged(meta.id, .working))
        return meta
    }

    private func reply(_ text: String) {
        transcripts.stub(sessionID: "s-1", cwd: api.path, messages: [
            ChatMessage(id: "u", role: .user, blocks: [.text("yap", presentation: nil)], timestampMs: nil, turnId: "u"),
            ChatMessage(id: "a", role: .assistant, blocks: [.text(text, presentation: nil)], timestampMs: nil, turnId: "a"),
        ])
    }

    /// Oturma süresi + üretim için bekler.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    func testUnseenFinishWithShortReplyIsShownVerbatim() async {
        let meta = agent()
        reply("Testler yeşil. Commit atayım mı?")

        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()

        XCTAssertEqual(feed.events.count, 1)
        let event = feed.events.first
        XCTAssertEqual(event?.kind, .finished)
        XCTAssertEqual(event?.summary, "Testler yeşil. Commit atayım mı?")
        XCTAssertEqual(event?.needsUser, true, "soru işaretiyle biten mesaj")
        XCTAssertEqual(event?.location, "api · main")
        XCTAssertTrue(summarizer.requests.isEmpty, "kısa mesaj LLM'e gitmez")
    }

    func testLongReplyIsSummarizedAndFailureFallsBackToTruncation() async {
        let meta = agent()
        let long = String(repeating: "uzun cevap ", count: 60)
        reply(long)
        summarizer.stub(.success(TerminalDigest(summary: "Özet", needsUser: false)))

        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()
        XCTAssertEqual(feed.events.first?.summary, "Özet")
        XCTAssertEqual(summarizer.requests.count, 1)

        summarizer.stub(.failure(.digestFailed(detail: "x")))
        coordinator.apply(.statusChanged(meta.id, .working))
        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()
        let fallback = feed.events.first?.summary ?? ""
        XCTAssertTrue(fallback.hasSuffix("(truncated)"), fallback)
    }

    func testSummarizerQuestionFlagIsVetoedWhenTheMessageHasNoQuestionMark() async {
        let meta = agent()
        reply(String(repeating: "Derleme geçti ama oyun içinde test etmedim. ", count: 10))
        summarizer.stub(.success(TerminalDigest(summary: "Özet", needsUser: true)))

        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()
        XCTAssertEqual(feed.events.first?.needsUser, false, "uyarı soru değildir")

        reply(String(repeating: "uzun rapor ", count: 40) + "Commit atayım mı?")
        coordinator.apply(.statusChanged(meta.id, .working))
        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()
        XCTAssertEqual(feed.events.first?.needsUser, true)
    }

    /// Türkçe ajan soruyu `?`'sız, soru ekiyle sorar — haiku bayrağı veto edilmez.
    func testTurkishQuestionWithoutQuestionMarkAsksTheUser() async {
        let meta = agent()
        reply(String(repeating: "Tahmini efor 1,5–3 gün. ", count: 20)
              + "\n\nBaşlamadan önce iki konuda kararınız gerekiyor: migration kaldırılsın mı, "
              + "yoksa tek seferlik mi kalsın; ve en küçük genişlik ortak 180 mi olsun.")
        summarizer.stub(.success(TerminalDigest(summary: "2 karar gerekli: … mi olsun?", needsUser: true)))

        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()
        XCTAssertEqual(feed.events.first?.needsUser, true, "soru eki de sorudur")
    }

    /// Son satırı soru olan mesaj haiku `false` dese de kullanıcıya sorar.
    func testMessageEndingWithAQuestionOverridesTheSummarizer() async {
        let meta = agent()
        reply(String(repeating: "uzun rapor ", count: 40) + "\nCommit atayım mı")
        summarizer.stub(.success(TerminalDigest(summary: "Özet", needsUser: false)))

        coordinator.apply(.statusChanged(meta.id, .waitingUnseen))
        await settle()
        XCTAssertEqual(feed.events.first?.needsUser, true)
    }

    func testQuestionHeuristics() {
        XCTAssertTrue(TerminalDigestCoordinator.looksLikeQuestion("Bitti.\nCommit atayım mı?\n"))
        XCTAssertTrue(TerminalDigestCoordinator.looksLikeQuestion("Hangisi olsun: sol mu sağ mı."))
        XCTAssertTrue(TerminalDigestCoordinator.looksLikeQuestion("Devam edeyim mi"))
        XCTAssertTrue(TerminalDigestCoordinator.looksLikeQuestion("Onaylıyor musunuz"))
        XCTAssertFalse(TerminalDigestCoordinator.looksLikeQuestion("Neden? Çünkü cache boştu.\nDüzelttim."))
        XCTAssertFalse(TerminalDigestCoordinator.looksLikeQuestion("Derleme geçti ama oyun içinde test etmedim."))
        XCTAssertFalse(TerminalDigestCoordinator.containsQuestion("Kimi dosyalar eksikti, mimari değişmedi, mutex eklendi."))
        XCTAssertTrue(TerminalDigestCoordinator.containsQuestion("Migration kaldırılsın mı, kalsın mı karar ver."))
    }

    func testWatchedTerminalReportsEvenAFinishTheUserSaw() async {
        let meta = agent()
        reply("Bitti.")
        coordinator.apply(.statusChanged(meta.id, .waitingFocused))
        await settle()
        XCTAssertEqual(feed.events.map(\.summary), ["Bitti."])
    }

    func testUnwatchedBouncesNonClaudeAndDisabledGateProduceNothing() async {
        let unwatched = agent(watched: false)
        coordinator.apply(.statusChanged(unwatched.id, .waitingUnseen))

        let bounce = agent()
        coordinator.apply(.statusChanged(bounce.id, .waitingUnseen))
        coordinator.apply(.statusChanged(bounce.id, .working))

        let shell = agent(provider: nil, session: nil)
        coordinator.apply(.statusChanged(shell.id, .waitingUnseen))
        let codex = agent(provider: .codex, session: nil)
        coordinator.apply(.statusChanged(codex.id, .waitingUnseen))
        await settle()
        XCTAssertTrue(feed.events.isEmpty)

        enabled = false
        let gated = agent()
        coordinator.apply(.statusChanged(gated.id, .waitingUnseen))
        await settle()
        XCTAssertTrue(feed.events.isEmpty)
    }

    func testAwaitingDecisionAndErrorProduceCards() async {
        let blocked = agent()
        terminals.apply(.awaitingDecisionChanged(blocked.id, true))
        coordinator.apply(.awaitingDecisionChanged(blocked.id, true))
        let broken = agent(session: nil)
        coordinator.apply(.statusChanged(broken.id, .error))
        await settle()

        let kinds = Dictionary(uniqueKeysWithValues: feed.events.map { ($0.terminalID, $0) })
        XCTAssertEqual(kinds[blocked.id]?.kind, .needsDecision)
        XCTAssertEqual(kinds[blocked.id]?.needsUser, true)
        XCTAssertEqual(kinds[broken.id]?.kind, .failed)
        XCTAssertEqual(kinds[broken.id]?.summary, "Stopped with an error.")
        XCTAssertTrue(summarizer.requests.isEmpty)
    }

    func testExitForgetsAndSpawnAdoptsARestoredSession() async throws {
        let closed = agent()
        coordinator.apply(.exited(closed.id, code: 0))
        XCTAssertFalse(watchList.isWatched(closed))

        let config = FakeConfigService()
        await config.updateUIState { $0.orchestratorWatchedSessions = ["s-restored"] }
        watchList = OrchestratorWatchList(config: config)
        await watchList.load(matching: [])
        setUpCoordinator()
        let restored = agent(session: "s-restored", watched: false)
        XCTAssertEqual(watchList.terminalIDs, [restored.id], "resume edilen terminal izlemeye geri bağlanır")
    }

    func testDecisionResolvedBeforeSettleIsDropped() async {
        let blocked = agent()
        coordinator.apply(.awaitingDecisionChanged(blocked.id, true))
        coordinator.apply(.awaitingDecisionChanged(blocked.id, false))
        await settle()
        XCTAssertTrue(feed.events.isEmpty)
    }
}
