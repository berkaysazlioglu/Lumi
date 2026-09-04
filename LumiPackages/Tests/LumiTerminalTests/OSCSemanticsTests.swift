import Foundation
import XCTest
@testable import LumiTerminal

/// Faz 4.8 semantik katmanı: ham `(code, payload)` → Lumi olayı.
/// Electron paritesindeki tüm title/notification kuralları burada yaşar.
final class OSCSemanticsTests: XCTestCase {
    private let chain = OSCSemanticsChain(OSCSemanticsDefaults.all)

    private func interpret(
        code: Int,
        _ payload: String,
        hint: AgentHint = .unknown
    ) -> [OSCEvent] {
        chain.interpret(OSCRawEvent(code: code, payload: payload), hint: hint)
    }

    private func title(code: Int = 0, _ payload: String) -> OSCTitleEvent? {
        guard case .title(let event)? = interpret(code: code, payload).first else { return nil }
        return event
    }

    // MARK: - Title semantiği (generic)

    func testGenericTitleIsWorkingWithoutHint() {
        let event = title("✦ Thinking")
        XCTAssertEqual(event?.isWorking, true)
        XCTAssertEqual(event?.displayTitle, "Thinking")
        XCTAssertNil(event?.providerHint)
    }

    func testStripsLeadingCharacterEvenWithoutIcon() {
        // `/^.\s*/` paritesi: ikonsuz title'ın ilk harfi de gider (bilinen trade-off)
        let event = title(code: 2, "hello")
        XCTAssertEqual(event?.rawTitle, "hello")
        XCTAssertEqual(event?.displayTitle, "ello")
    }

    func testEmptyTitleMakesNoDecision() {
        let event = title("")
        XCTAssertNil(event?.isWorking)
        XCTAssertNil(event?.displayTitle)
    }

    // MARK: - Claude semantiği

    func testIdleMarkTitle() {
        let event = title("\u{2733} task done")
        XCTAssertEqual(event?.isWorking, false)
        XCTAssertEqual(event?.providerHint, .claude)
        XCTAssertEqual(event?.displayTitle, "task done")
    }

    func testClaudeWordBoundaryHint() {
        let event = title("⠼ claude is working")
        XCTAssertEqual(event?.providerHint, .claude)
        XCTAssertEqual(event?.isWorking, true)
    }

    func testClaudeCodeSubstringHint() {
        XCTAssertEqual(title(code: 2, "⠼ Claude Code session")?.providerHint, .claude)
    }

    func testClaudetteIsNotClaude() {
        XCTAssertNil(title("x claudette working")?.providerHint)
    }

    func testPermissionRequestVariants() {
        let payloads = [
            "Claude needs your permission",
            "needs your permission to use Bash",
            "Permission required",
        ]
        for payload in payloads {
            XCTAssertEqual(
                interpret(code: 9, payload),
                [.notification(.permissionRequest)],
                payload
            )
        }
    }

    /// İzin sinyali turn-complete'e karışmamalı (kuyruk araya prompt sokmasın).
    func testPermissionWinsOverTurnCompleteInChainOrder() {
        XCTAssertEqual(
            interpret(code: 9, "Claude needs your permission before the task is done"),
            [.notification(.permissionRequest)]
        )
    }

    // MARK: - Codex semantiği

    func testCodexTurnCompleteVariants() {
        let payloads = [
            "Turn complete",
            "task finished",
            "Waiting for input",
            "all idle now",
            "in idle state",
        ]
        for payload in payloads {
            XCTAssertEqual(
                interpret(code: 9, payload),
                [.notification(.codexTurnComplete)],
                payload
            )
        }
    }

    func testUnknownNotificationProducesNoEvent() {
        XCTAssertTrue(interpret(code: 9, "build failed").isEmpty)
    }

    // MARK: - Tanınmayan kodlar

    func testUnhandledCodesProduceNoEvent() {
        XCTAssertTrue(interpret(code: 52, "c;aGVsbG8=").isEmpty)
        XCTAssertTrue(interpret(code: 7, "file:///tmp").isEmpty)
    }

    // MARK: - Zincir sözleşmesi

    /// Bir sequence başına EN FAZLA tek olay: aksi halde aynı title iki kez
    /// yayınlanır (status/başlık çift tetiklenir).
    func testChainStopsAtFirstMatch() {
        XCTAssertEqual(interpret(code: 0, "\u{2733} idle").count, 1)
        XCTAssertEqual(interpret(code: 9, "Turn complete").count, 1)
    }

    /// Hint semantiklere geçirilir — ajan-duyarlı yorum yazılabilsin (OCP).
    func testHintIsPassedThroughToSemantics() {
        let spy = HintSpySemantics()
        _ = OSCSemanticsChain([spy]).interpret(
            OSCRawEvent(code: 0, payload: "x"),
            hint: .codex
        )
        XCTAssertEqual(spy.seenHints, [.codex])
    }
}

/// Gördüğü hint'leri kaydeden, olay üretmeyen semantik.
private final class HintSpySemantics: OSCSemantics, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AgentHint] = []

    var seenHints: [AgentHint] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func interpret(code: Int, payload: String, hint: AgentHint) -> [OSCEvent] {
        lock.lock()
        storage.append(hint)
        lock.unlock()
        return []
    }
}
