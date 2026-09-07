import LumiKit
import XCTest
@testable import LumiTerminal

/// Karar 45: hook olayı → durum etkisi tablosu (Orca `normalizeClaudeEvent` /
/// `normalizeCodexEvent` çekirdeği).
final class AgentHookStatusReducerTests: XCTestCase {
    private var reducer = AgentHookStatusReducer()
    private let terminal = TerminalID()

    override func setUp() {
        super.setUp()
        reducer = AgentHookStatusReducer()
    }

    private func event(
        _ kind: AgentHookEventKind,
        provider: AgentProvider = .claude,
        agentID: String? = nil,
        teammateName: String? = nil,
        toolName: String? = nil,
        source: String? = nil,
        trigger: String? = nil,
        isInterrupt: Bool = false,
        promptHead: String? = nil,
        background: [String]? = nil
    ) -> AgentHookEvent {
        AgentHookEvent(
            provider: provider, terminalID: terminal, kind: kind, agentID: agentID,
            teammateName: teammateName, toolName: toolName, source: source, trigger: trigger,
            isInterrupt: isInterrupt, promptHead: promptHead, runningBackgroundAgentIDs: background
        )
    }

    // MARK: - Temel eşleme

    func testFirstEventBindsAndRecordsProvider() {
        XCTAssertFalse(reducer.isBound)
        _ = reducer.reduce(event(.userPromptSubmit, provider: .codex))
        XCTAssertTrue(reducer.isBound)
        XCTAssertEqual(reducer.provider, .codex)
    }

    func testPromptToolsAndStopFollowTheTurn() {
        XCTAssertEqual(reducer.reduce(event(.userPromptSubmit)), [.decisionResolved, .working])
        XCTAssertEqual(reducer.reduce(event(.preToolUse, toolName: "Bash")), [.working])
        XCTAssertEqual(reducer.reduce(event(.postToolUse, toolName: "Bash")), [.working])
        XCTAssertEqual(reducer.reduce(event(.postToolUseFailure, toolName: "Bash")), [.working])
        XCTAssertEqual(reducer.reduce(event(.stop)), [.decisionResolved, .turnEnded])
        XCTAssertFalse(reducer.isRunning)
    }

    func testStopFailureEndsTurnLikeStop() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.stopFailure)), [.decisionResolved, .turnEnded])
    }

    func testSessionStartFromIdleSourcesResetsToIdle() {
        _ = reducer.reduce(event(.userPromptSubmit))
        for source in ["startup", "resume", "clear"] {
            _ = reducer.reduce(event(.userPromptSubmit))
            XCTAssertEqual(reducer.reduce(event(.sessionStart, source: source)), [.decisionResolved, .sessionIdle], source)
            XCTAssertFalse(reducer.isRunning)
        }
    }

    func testSessionStartFromCompactOrUnknownSourceIsIgnoredForClaude() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.sessionStart, source: "compact")), [])
        XCTAssertEqual(reducer.reduce(event(.sessionStart, source: "mystery")), [])
        XCTAssertTrue(reducer.isRunning, "compact turn ortasında ateşler; canlı turn idle'a çekilmez")
    }

    /// Lumi sapması: Orca Codex `SessionStart`'ı `working` sayar; taze TUI
    /// boştadır, hayalet spinner yerine idle.
    func testCodexSessionStartIsIdleRegardlessOfSource() {
        XCTAssertEqual(reducer.reduce(event(.sessionStart, provider: .codex)), [.decisionResolved, .sessionIdle])
    }

    func testSessionEndUnbindsAndClearsProvider() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.sessionEnd)), [.sessionEnded])
        XCTAssertFalse(reducer.isBound)
        XCTAssertNil(reducer.provider)
        XCTAssertFalse(reducer.isRunning)
    }

    func testCompactContinuationPromptDoesNotStartTurn() {
        let effects = reducer.reduce(event(
            .userPromptSubmit,
            promptHead: "This session is being continued from a previous conversation"
        ))
        XCTAssertEqual(effects, [])
        XCTAssertFalse(reducer.isRunning)
    }

    func testManualPostCompactEndsTurnButAutoDoesNot() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.postCompact, trigger: "auto")), [])
        XCTAssertTrue(reducer.isRunning)
        XCTAssertEqual(reducer.reduce(event(.postCompact, trigger: "manual")), [.decisionResolved, .turnEnded])
    }

    func testUnknownEventsAreIgnored() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.unknown("Notification"))), [])
        XCTAssertTrue(reducer.isRunning)
    }

    // MARK: - Karar (izin / soru)

    func testPermissionRequestRaisesDecisionWithoutEndingTurn() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.permissionRequest, toolName: "Bash")), [.decisionRequested, .working])
    }

    func testApprovedToolCompletionResolvesDecision() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.preToolUse, toolName: "Bash"))
        _ = reducer.reduce(event(.permissionRequest, toolName: "Bash"))
        XCTAssertEqual(reducer.reduce(event(.postToolUse, toolName: "Bash")), [.decisionResolved, .working])
    }

    /// Paralel araçlar: bekleyen izin başka bir aracın bitişiyle kapanmaz.
    func testUnrelatedParallelToolCompletionKeepsDecisionPending() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.preToolUse, toolName: "Read"))
        _ = reducer.reduce(event(.preToolUse, toolName: "Bash"))
        _ = reducer.reduce(event(.permissionRequest, toolName: "Bash"))
        XCTAssertEqual(reducer.reduce(event(.postToolUse, toolName: "Read")), [.working])
        XCTAssertEqual(reducer.reduce(event(.postToolUse, toolName: "Bash")), [.decisionResolved, .working])
    }

    func testDeniedPermissionResolvesWhenModelMovesToAnotherTool() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.permissionRequest, toolName: "Bash"))
        XCTAssertEqual(reducer.reduce(event(.preToolUse, toolName: "Read")), [.decisionResolved, .working])
    }

    func testAskUserQuestionPreToolUseIsADecisionNotWork() {
        _ = reducer.reduce(event(.userPromptSubmit))
        XCTAssertEqual(reducer.reduce(event(.preToolUse, toolName: "AskUserQuestion")), [.decisionRequested, .working])
        XCTAssertEqual(reducer.reduce(event(.postToolUse, toolName: "AskUserQuestion")), [.decisionResolved, .working])
    }

    func testStopResolvesPendingDecision() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.permissionRequest, toolName: "Bash"))
        XCTAssertEqual(reducer.reduce(event(.stop)), [.decisionResolved, .turnEnded])
    }

    // MARK: - Alt ajan kadrosu

    func testLeadStopWithWorkingSubagentKeepsWorkingUntilSubagentStops() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.subagentStart, agentID: "sub-1"))
        XCTAssertEqual(reducer.reduce(event(.stop)), [.decisionResolved, .working])
        XCTAssertEqual(reducer.reduce(event(.subagentStop, agentID: "sub-1")), [.turnEnded])
    }

    func testSubagentToolEventsDoNotOwnTheLeadTurn() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.stop))
        // Kaçırılmış SubagentStart: çocuğun araç trafiği onu kadroya alır.
        XCTAssertEqual(reducer.reduce(event(.preToolUse, agentID: "sub-9", toolName: "Bash")), [.working])
        XCTAssertFalse(reducer.isLeadRunning)
        XCTAssertEqual(reducer.reduce(event(.subagentStop, agentID: "sub-9")), [.turnEnded])
    }

    func testBackgroundTasksInventoryOnStopIsAuthoritative() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.subagentStart, agentID: "gone"))
        _ = reducer.reduce(event(.subagentStart, agentID: "alive"))
        XCTAssertEqual(reducer.reduce(event(.stop, background: ["alive"])), [.decisionResolved, .working])
        XCTAssertEqual(reducer.workingSubagents, ["alive"])
        XCTAssertEqual(reducer.reduce(event(.stop, background: [])), [.decisionResolved, .turnEnded])
    }

    func testInterruptedStopClearsRoster() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.subagentStart, agentID: "sub-1"))
        XCTAssertEqual(reducer.reduce(event(.stop, isInterrupt: true)), [.decisionResolved, .turnEnded])
        XCTAssertTrue(reducer.workingSubagents.isEmpty)
    }

    func testTeammateIdleParksMatchingTeammateOnly() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.subagentStart, agentID: "areviewer-1a2b"))
        _ = reducer.reduce(event(.subagentStart, agentID: "abuilder-9f"))
        _ = reducer.reduce(event(.stop))
        XCTAssertEqual(reducer.reduce(event(.teammateIdle, teammateName: "reviewer")), [.working])
        XCTAssertEqual(reducer.workingSubagents, ["abuilder-9f"])
        XCTAssertEqual(reducer.reduce(event(.teammateIdle, teammateName: "builder")), [.turnEnded])
    }

    func testChildPermissionIsResolvedWhenChildStops() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.permissionRequest, agentID: "sub-1", toolName: "Bash"))
        XCTAssertEqual(reducer.reduce(event(.subagentStop, agentID: "sub-1")), [.decisionResolved, .working])
    }

    // MARK: - Kesme çıkarımı

    func testInferInterruptEndsLeadTurnOnlyWithoutChildren() {
        XCTAssertEqual(reducer.inferInterrupt(), [], "bağlı değilken çıkarım yok")
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.subagentStart, agentID: "sub-1"))
        XCTAssertEqual(reducer.inferInterrupt(), [], "canlı çocuk varken Ctrl+C çocuğu durdurmaz")
        _ = reducer.reduce(event(.subagentStop, agentID: "sub-1"))
        _ = reducer.reduce(event(.preToolUse, toolName: "Bash"))
        XCTAssertEqual(reducer.inferInterrupt(), [.decisionResolved, .turnEnded])
        XCTAssertFalse(reducer.isRunning)
    }

    func testResetDropsEverything() {
        _ = reducer.reduce(event(.userPromptSubmit))
        _ = reducer.reduce(event(.subagentStart, agentID: "sub-1"))
        reducer.reset()
        XCTAssertFalse(reducer.isBound)
        XCTAssertNil(reducer.provider)
        XCTAssertFalse(reducer.isRunning)
    }
}
