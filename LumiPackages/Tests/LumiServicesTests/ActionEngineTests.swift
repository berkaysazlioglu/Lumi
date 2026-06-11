import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Faz 5 çıkış kriteri: wait_for rolling-ring + timeout (karar 11 düzeltmesi —
/// pattern chunk sınırına denk gelse de eşleşir; Electron tek-chunk'tı).
final class ActionEngineTests: XCTestCase {
    private func makeStream(
        chunks: [String],
        chunkDelayMs: Int = 0
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                for chunk in chunks {
                    if chunkDelayMs > 0 {
                        try? await Task.sleep(for: .milliseconds(chunkDelayMs))
                    }
                    continuation.yield(chunk)
                }
                // stream açık kalır (canlı terminal) — timeout testi için finish yok
            }
        }
    }

    func testPatternSplitAcrossChunksMatches() async throws {
        let stream = makeStream(chunks: ["Project cre", "ated: /tmp/x\n"])
        try await ActionEngine.waitFor(
            pattern: "Project created:",
            timeoutMs: 2000,
            stream: stream,
            actionID: "test",
            stepIndex: 0
        )
    }

    func testRegexPatternMatches() async throws {
        let stream = makeStream(chunks: ["build #", "42 finished\n"])
        try await ActionEngine.waitFor(
            pattern: #"build #\d+ finished"#,
            timeoutMs: 2000,
            stream: stream,
            actionID: "test",
            stepIndex: 0
        )
    }

    func testMatchSurvivesRingTrimming() async throws {
        // 4KB'lik ring: büyük çöp prefix'i sonrası gelen pattern yine yakalanır
        let garbage = String(repeating: "x", count: 10_000)
        let stream = makeStream(chunks: [garbage, "DONE-MARKER"])
        try await ActionEngine.waitFor(
            pattern: "DONE-MARKER",
            timeoutMs: 2000,
            stream: stream,
            actionID: "test",
            stepIndex: 0
        )
    }

    func testTimeoutThrowsActionStepTimedOut() async {
        let stream = makeStream(chunks: ["nothing relevant"], chunkDelayMs: 10)
        do {
            try await ActionEngine.waitFor(
                pattern: "never-appears",
                timeoutMs: 100,
                stream: stream,
                actionID: "my-action",
                stepIndex: 3
            )
            XCTFail("timeout fırlatmalıydı")
        } catch let error as LumiError {
            XCTAssertEqual(error, .actionStepTimedOut(actionID: "my-action", step: 3))
        } catch {
            XCTFail("LumiError bekleniyordu: \(error)")
        }
    }

    func testInvalidPatternThrowsBeforeWaiting() async {
        let stream = makeStream(chunks: [])
        do {
            try await ActionEngine.waitFor(
                pattern: "([unclosed",
                timeoutMs: 100,
                stream: stream,
                actionID: "a",
                stepIndex: 0
            )
            XCTFail("geçersiz regex hata fırlatmalıydı")
        } catch let error as LumiError {
            guard case .underlying = error else {
                return XCTFail("beklenmeyen hata: \(error)")
            }
        } catch {
            XCTFail("LumiError bekleniyordu")
        }
    }

    @MainActor
    func testExecuteRunsStepsSequentially() async throws {
        let terminal = StubTerminalService()
        let engine = ActionEngine(terminal: terminal)
        let builder = AgentCommandBuilder(
            tempDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("lumi-engine-\(UUID().uuidString)")
        )
        let action = Action(
            id: "seq",
            label: "Sequential",
            steps: [
                .write(content: "echo one\r"),
                .delay(ms: 10),
                .write(content: "echo two\r"),
            ]
        )

        let meta = try await engine.execute(
            action, repoPath: "/tmp", provider: .claude, builder: builder
        )
        XCTAssertEqual(terminal.spawnCalls.first?.task, "Sequential")
        XCTAssertEqual(terminal.writeCalls.map(\.text), ["echo one\r", "echo two\r"])
        XCTAssertEqual(terminal.writeCalls.first?.id, meta.id)
    }
}
