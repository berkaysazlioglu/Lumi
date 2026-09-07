import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// Karar 45: hook otoritesinin pipeline'daki etkisi — OSC sezgileri susar,
/// hook etkileri durum makinesine iner, kesme çıkarımı zamanlayıcıyla çalışır.
final class TerminalPipelineHookTests: XCTestCase {
    private let terminal = TerminalID()

    private func makePipeline(initialProvider: AgentProvider? = nil) -> (
        pipeline: TerminalPipeline, silence: TestScheduler, interrupt: TestScheduler
    ) {
        let queue = DispatchQueue(label: "lumi.test.pipeline.hooks.\(UUID().uuidString)")
        let silence = TestScheduler()
        let interrupt = TestScheduler()
        let pipeline = TerminalPipeline(
            queue: queue,
            coalescerScheduler: TestScheduler(),
            silenceScheduler: silence,
            interruptScheduler: interrupt,
            initialProvider: initialProvider
        )
        return (pipeline, silence, interrupt)
    }

    private func hook(
        _ kind: AgentHookEventKind, provider: AgentProvider = .claude, toolName: String? = nil, agentID: String? = nil
    ) -> AgentHookEvent {
        AgentHookEvent(provider: provider, terminalID: terminal, kind: kind, agentID: agentID, toolName: toolName)
    }

    // MARK: - Hook → durum

    func testHookTurnDrivesWorkingThenWaiting() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        XCTAssertEqual(pipeline.statusMachine.status, .working)
        pipeline.processHookEvent(hook(.stop))
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)
    }

    func testSessionStartResetsToIdle() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        pipeline.processHookEvent(hook(.stop))
        pipeline.processHookEvent(AgentHookEvent(provider: .claude, terminalID: terminal, kind: .sessionStart, source: "startup"))
        XCTAssertEqual(pipeline.statusMachine.status, .idle)
    }

    func testPermissionRequestRaisesDecisionFlagWithoutChangingStatus() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        pipeline.processHookEvent(hook(.permissionRequest, toolName: "Bash"))
        XCTAssertTrue(pipeline.decisionTracker.isAwaitingDecision)
        XCTAssertEqual(pipeline.statusMachine.status, .working)
        pipeline.processHookEvent(hook(.postToolUse, toolName: "Bash"))
        XCTAssertFalse(pipeline.decisionTracker.isAwaitingDecision)
    }

    // MARK: - Otorite: OSC susar

    func testOSCTitleNoLongerDrivesStatusOnceBound() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        XCTAssertEqual(pipeline.statusMachine.status, .working)

        // ✳ idle işareti hook'lar bağlıyken durumu düşüremez…
        _ = pipeline.processOutput(Data("\u{1B}]0;\u{2733} claude\u{07}".utf8))
        XCTAssertEqual(pipeline.statusMachine.status, .working)
        // …ama başlık metni hâlâ akar.
        let titles = Recorder<String>()
        pipeline.onDisplayTitle = { titles.append($0) }
        _ = pipeline.processOutput(Data("\u{1B}]0;✳ Fixing tests\u{07}".utf8))
        XCTAssertEqual(titles.values.last, "Fixing tests")
    }

    func testOSCPermissionNotificationIsIgnoredOnceBound() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        _ = pipeline.processOutput(Data("\u{1B}]9;Claude needs your permission\u{07}".utf8))
        XCTAssertFalse(pipeline.decisionTracker.isAwaitingDecision)
    }

    func testCodexSilenceHeuristicIsIgnoredOnceBound() {
        let (pipeline, silence, _) = makePipeline(initialProvider: .codex)
        pipeline.processHookEvent(hook(.userPromptSubmit, provider: .codex))
        pipeline.processHookEvent(hook(.stop, provider: .codex))
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)

        _ = pipeline.processOutput(Data("some output".utf8))
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen, "çıktı aktivitesi working'e çekmemeli")
        XCTAssertFalse(silence.isScheduled, "silence timer'a dokunulmamalı")
        _ = pipeline.processInput(Data("\r".utf8))
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen, "Enter sezgisi de susar")
    }

    func testHeuristicsResumeAfterSessionEnd() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        pipeline.processHookEvent(hook(.sessionEnd))
        XCTAssertEqual(pipeline.statusMachine.status, .idle)
        XCTAssertFalse(pipeline.hookReducer.isBound)

        _ = pipeline.processOutput(Data("\u{1B}]0;Working on it\u{07}".utf8))
        XCTAssertEqual(pipeline.statusMachine.status, .working, "hook otoritesi kalktı, OSC yine sürer")
    }

    // MARK: - Kesme çıkarımı

    func testEscapeWhileWorkingSchedulesInterruptAndSettlesToWaiting() {
        let (pipeline, _, interrupt) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))

        _ = pipeline.processInput(Data([0x1B]))
        XCTAssertTrue(interrupt.isScheduled)
        XCTAssertEqual(interrupt.lastInterval, InterruptSettleTimer.defaultInterval)

        interrupt.fire()
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)
    }

    func testCtrlCSchedulesInterruptButArrowKeysDoNot() {
        let (pipeline, _, interrupt) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))

        _ = pipeline.processInput(Data("\u{1B}[A".utf8))
        XCTAssertFalse(interrupt.isScheduled, "ESC ile başlayan dizi kesme değildir")
        _ = pipeline.processInput(Data([0x03]))
        XCTAssertTrue(interrupt.isScheduled)
    }

    func testHookArrivalCancelsPendingInterruptInference() {
        let (pipeline, _, interrupt) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        _ = pipeline.processInput(Data([0x1B]))
        XCTAssertTrue(interrupt.isScheduled)

        pipeline.processHookEvent(hook(.preToolUse, toolName: "Bash"))
        XCTAssertFalse(interrupt.isScheduled)
        XCTAssertEqual(pipeline.statusMachine.status, .working)
    }

    func testEscapeIsNotAnInterruptWhenUnboundOrNotWorking() {
        let (pipeline, _, interrupt) = makePipeline()
        _ = pipeline.processInput(Data([0x1B]))
        XCTAssertFalse(interrupt.isScheduled, "hook yokken çıkarım yok")

        pipeline.processHookEvent(hook(.userPromptSubmit))
        pipeline.processHookEvent(hook(.stop))
        _ = pipeline.processInput(Data([0x1B]))
        XCTAssertFalse(interrupt.isScheduled, "beklerken Esc kesme değildir")
    }

    // MARK: - Sağlayıcı kimliği

    func testProviderIsReportedFromHookAndClearedOnSessionEnd() {
        let (pipeline, _, _) = makePipeline()
        let providers = Recorder<AgentProvider?>()
        pipeline.onProviderChange = { providers.append($0) }

        pipeline.processHookEvent(hook(.userPromptSubmit, provider: .codex))
        pipeline.processHookEvent(hook(.preToolUse, provider: .codex, toolName: "shell"))
        pipeline.processHookEvent(hook(.sessionEnd, provider: .codex))

        XCTAssertEqual(providers.values, [.codex, nil], "yalnız gerçek değişim yayılır")
    }

    func testProviderIsInferredFromTypedCommandBeforeAnyHook() {
        let (pipeline, _, _) = makePipeline()
        let providers = Recorder<AgentProvider?>()
        pipeline.onProviderChange = { providers.append($0) }

        _ = pipeline.processInput(Data("claude\r".utf8))
        XCTAssertEqual(providers.values, [.claude])
    }

    func testInitialProviderIsNotReReported() {
        let (pipeline, _, _) = makePipeline(initialProvider: .claude)
        let providers = Recorder<AgentProvider?>()
        pipeline.onProviderChange = { providers.append($0) }

        _ = pipeline.processInput(Data("claude --resume x\r".utf8))
        pipeline.processHookEvent(hook(.userPromptSubmit))
        XCTAssertTrue(providers.values.isEmpty)
    }

    func testFinishExitResetsHookAuthority() {
        let (pipeline, _, _) = makePipeline()
        pipeline.processHookEvent(hook(.userPromptSubmit))
        pipeline.finishExit(code: 0)
        XCTAssertFalse(pipeline.hookReducer.isBound)
        XCTAssertEqual(pipeline.statusMachine.status, .idle)
    }
}

private final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
