import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 145: tur başına bir bildirim, boşta/görülmüş chat'ten tekrar yok,
/// oturma süresi, kesme ve içerik.
@MainActor
final class AgentNotificationCoordinatorTests: XCTestCase {
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var notifications: FakeNotificationService!
    private var transcripts: FakeTerminalTranscripts!
    private var coordinator: AgentNotificationCoordinator!

    private let repoPath = "/p/api"

    override func setUp() async throws {
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        notifications = FakeNotificationService()
        transcripts = FakeTerminalTranscripts()
        coordinator = AgentNotificationCoordinator(
            service: service, terminals: terminals, notifications: notifications, transcripts: transcripts,
            checkoutLabel: { _ in "api / feature" }, settleDelay: .milliseconds(20)
        )
    }

    // MARK: - Yardımcılar

    private func agent(title: String? = "Fix login flow", session: String? = "s-1") -> TerminalMeta {
        var meta = TerminalMeta(id: TerminalID(), name: "claude", repoPath: repoPath, createdAt: Date(),
                                status: .idle, claudeSessionID: session, provider: .claude)
        meta.oscTitle = title
        send(.spawned(meta))
        return meta
    }

    /// Olay store'a ve koordinatöre aynı sırayla gider (canlıdaki iki tüketici).
    private func send(_ event: TerminalEvent) {
        terminals.apply(event)
        coordinator.apply(event)
    }

    private func reply(_ text: String) {
        transcripts.stub(sessionID: "s-1", cwd: repoPath, messages: [
            ChatMessage(id: "u", role: .user, blocks: [.text("yap", presentation: nil)], timestampMs: nil, turnId: "u"),
            ChatMessage(id: "a", role: .assistant, blocks: [.text(text, presentation: nil)], timestampMs: nil, turnId: "a"),
        ])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Bildirim DOĞMAMASI beklenen durumlar için oturma süresinin epey ötesi.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    // MARK: - Tetik

    func testFinishedTurnNotifiesOnceWithChatNameCheckoutAndLastMessage() async {
        let meta = agent()
        reply("**Done.** Tests are green.\n\n```swift\nlet x = 1\n```\nShall I commit?")
        send(.statusChanged(meta.id, .working))
        send(.statusChanged(meta.id, .waitingUnseen))
        await waitUntil { !notifications.delivered.isEmpty }

        XCTAssertEqual(notifications.delivered, [AgentNotification(
            terminalID: meta.id, kind: .finished, title: "Fix login flow",
            subtitle: "api / feature · Claude finished", body: "Done. Tests are green. Shall I commit?",
            isTerminalFocused: false, groupKey: repoPath
        )])
    }

    func testIdleAndSeenChatsNeverNotify() async {
        let meta = agent()
        // Hiç çalışmamış terminal: odak/görülme geçişleri kenar değildir.
        send(.statusChanged(meta.id, .waitingFocused))
        send(.statusChanged(meta.id, .waitingSeen))
        send(.statusChanged(meta.id, .waitingFocused))
        await settle()
        XCTAssertTrue(notifications.delivered.isEmpty)

        send(.statusChanged(meta.id, .working))
        send(.statusChanged(meta.id, .waitingFocused))
        await waitUntil { notifications.delivered.count == 1 }
        // Bitmiş turun görülmesi / bırakılması yeni bildirim üretmez (eski 5 dk tekrarı).
        send(.statusChanged(meta.id, .waitingSeen))
        send(.statusChanged(meta.id, .waitingFocused))
        send(.statusChanged(meta.id, .waitingSeen))
        await settle()
        XCTAssertEqual(notifications.delivered.count, 1)
        XCTAssertEqual(notifications.delivered.first?.isTerminalFocused, true, "turn odaktayken kapandı")
    }

    func testEveryRealTurnNotifiesAgain() async {
        let meta = agent()
        for turn in 1...2 {
            send(.statusChanged(meta.id, .working))
            send(.statusChanged(meta.id, .waitingUnseen))
            await waitUntil { notifications.delivered.count == turn }
        }
        XCTAssertEqual(notifications.delivered.count, 2)
    }

    func testWorkingAgainWithinSettleCancelsAndDismisses() async {
        let meta = agent()
        send(.statusChanged(meta.id, .working))
        send(.statusChanged(meta.id, .waitingUnseen))
        send(.statusChanged(meta.id, .working))
        await settle()

        XCTAssertTrue(notifications.delivered.isEmpty, "alt ajan / compaction'ın sahte bitişi")
        XCTAssertTrue(notifications.dismissed.contains(meta.id))
    }

    func testInterruptCancelsPendingFinish() async {
        let meta = agent()
        send(.statusChanged(meta.id, .working))
        send(.statusChanged(meta.id, .waitingUnseen))
        send(.interruptInferred(meta.id))
        await settle()
        XCTAssertTrue(notifications.delivered.isEmpty, "kullanıcı turu kendisi durdurdu")
    }

    func testFailureFromWorkingNotifiesButExitErrorFromIdleDoesNot() async {
        let idle = agent()
        send(.statusChanged(idle.id, .error))
        await settle()
        XCTAssertTrue(notifications.delivered.isEmpty)

        let meta = agent(session: nil)
        send(.statusChanged(meta.id, .working))
        send(.statusChanged(meta.id, .error))
        await waitUntil { !notifications.delivered.isEmpty }
        XCTAssertEqual(notifications.delivered.first?.kind, .failed)
        XCTAssertEqual(notifications.delivered.first?.subtitle, "api / feature · Claude failed")
        XCTAssertEqual(notifications.delivered.first?.body, "Claude stopped with an error.")
    }

    func testNeedsInputNotifiesUnlessResolvedWithinSettle() async {
        let meta = agent()
        send(.statusChanged(meta.id, .working))
        send(.awaitingDecisionChanged(meta.id, true))
        send(.awaitingDecisionChanged(meta.id, false))
        await settle()
        XCTAssertTrue(notifications.delivered.isEmpty)

        reply("I will run the migration.")
        send(.awaitingDecisionChanged(meta.id, true))
        await waitUntil { !notifications.delivered.isEmpty }
        let delivered = notifications.delivered.first
        XCTAssertEqual(delivered?.kind, .needsInput)
        XCTAssertEqual(delivered?.subtitle, "api / feature · Claude needs input")
        XCTAssertEqual(delivered?.body, "Waiting for your permission or answer.")
    }

    func testExitCancelsAndRemovesDelivered() async {
        let meta = agent()
        send(.statusChanged(meta.id, .working))
        send(.statusChanged(meta.id, .waitingUnseen))
        send(.exited(meta.id, code: 0))
        await settle()
        XCTAssertTrue(notifications.delivered.isEmpty)
        XCTAssertEqual(notifications.removedTerminals, [meta.id])
    }

    // MARK: - Metin

    func testTitleFallsBackToAgentLabelAndTruncates() {
        XCTAssertEqual(AgentNotificationText.title(displayTitle: "  ", provider: .codex), "Codex")
        let long = String(repeating: "a", count: 200)
        let title = AgentNotificationText.title(displayTitle: long, provider: .claude)
        XCTAssertEqual(title.count, AgentNotificationText.titleLimit)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testBodyIsPlainSingleLineAndBounded() {
        let markdown = "# Summary\n- **one** `two`\n> three\n" + String(repeating: "word ", count: 80)
        let body = AgentNotificationText.body(kind: .finished, lastMessage: markdown, provider: .claude)
        XCTAssertTrue(body.hasPrefix("Summary one two three word"))
        XCTAssertEqual(body.count, AgentNotificationText.bodyLimit)
        XCTAssertFalse(body.contains("\n"))
        XCTAssertEqual(
            AgentNotificationText.body(kind: .finished, lastMessage: "```\n```", provider: .claude),
            "Claude finished its turn."
        )
    }
}
