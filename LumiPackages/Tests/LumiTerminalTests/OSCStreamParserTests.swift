import XCTest
@testable import LumiTerminal

final class OSCStreamParserTests: XCTestCase {
    private var parser = OSCStreamParser()

    override func setUp() {
        super.setUp()
        parser = OSCStreamParser()
    }

    private func osc(_ body: String, terminator: String = "\u{07}") -> String {
        "\u{1B}]\(body)\(terminator)"
    }

    private func titleEvent(_ events: [OSCEvent]) -> OSCTitleEvent? {
        guard case .title(let event)? = events.first else { return nil }
        return event
    }

    // MARK: - Form ve terminatörler

    func testTitleWithBelTerminator() {
        let event = titleEvent(parser.feed(osc("0;✦ Thinking")))
        XCTAssertEqual(event?.isWorking, true)
        XCTAssertEqual(event?.displayTitle, "Thinking")
        XCTAssertNil(event?.providerHint)
    }

    func testTitleWithStTerminator() {
        let event = titleEvent(parser.feed(osc("2;hello", terminator: "\u{1B}\\")))
        XCTAssertEqual(event?.rawTitle, "hello")
        // `/^.\s*/` paritesi: ikonsuz title'ın ilk harfi de gider (spec/10 bilinen trade-off)
        XCTAssertEqual(event?.displayTitle, "ello")
    }

    func testSequenceSplitAcrossFeeds() {
        XCTAssertTrue(parser.feed("\u{1B}").isEmpty)
        XCTAssertTrue(parser.feed("]0;he").isEmpty)
        let event = titleEvent(parser.feed("llo\u{07}"))
        XCTAssertEqual(event?.rawTitle, "hello")
    }

    // MARK: - Claude idle / hint semantiği

    func testIdleMarkTitle() {
        let event = titleEvent(parser.feed(osc("0;\u{2733} task done")))
        XCTAssertEqual(event?.isWorking, false)
        XCTAssertEqual(event?.providerHint, .claude)
        XCTAssertEqual(event?.displayTitle, "task done")
    }

    func testClaudeWordBoundaryHint() {
        let event = titleEvent(parser.feed(osc("0;⠼ claude is working")))
        XCTAssertEqual(event?.providerHint, .claude)
        XCTAssertEqual(event?.isWorking, true)
    }

    func testClaudeCodeSubstringHint() {
        let event = titleEvent(parser.feed(osc("2;⠼ Claude Code session")))
        XCTAssertEqual(event?.providerHint, .claude)
    }

    func testClaudetteIsNotClaude() {
        let event = titleEvent(parser.feed(osc("0;x claudette working")))
        XCTAssertNil(event?.providerHint)
    }

    func testEmptyTitleMakesNoDecision() {
        let event = titleEvent(parser.feed(osc("0;")))
        XCTAssertNil(event?.isWorking)
        XCTAssertNil(event?.displayTitle)
    }

    // MARK: - OSC 9 bildirimleri

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
                OSCStreamParser.interpretNotification(payload),
                .codexTurnComplete,
                payload
            )
        }
    }

    func testGenericNotification() {
        XCTAssertEqual(OSCStreamParser.interpretNotification("build failed"), .generic)
    }

    func testOSC9EventEmitted() {
        let events = parser.feed(osc("9;Codex turn complete"))
        guard case .notification(.codexTurnComplete)? = events.first else {
            return XCTFail("turn-complete bekleniyordu: \(events)")
        }
    }

    // MARK: - Düşürme ve koruma davranışları

    func testOtherOSCCommandsDropped() {
        XCTAssertTrue(parser.feed(osc("52;c;aGVsbG8=")).isEmpty)
        XCTAssertTrue(parser.feed(osc("8;;http://example.com")).isEmpty)
    }

    func testOversizeBufferDiscarded() {
        let big = String(repeating: "a", count: OSCStreamParser.maxBufferLength + 500)
        XCTAssertTrue(parser.feed("\u{1B}]0;" + big + "\u{07}").isEmpty)
        // Parser ground'a döndü; sonraki sequence normal işler
        XCTAssertNotNil(titleEvent(parser.feed(osc("0;ok"))))
    }

    func testEscInsideBodyStartsNewSequence() {
        let events = parser.feed("\u{1B}]0;abandoned\u{1B}]2;real\u{07}")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(titleEvent(events)?.rawTitle, "real")
    }

    func testPlainTextAndCSIProduceNothing() {
        XCTAssertTrue(parser.feed("hello \u{1B}[31mworld\u{1B}[0m").isEmpty)
    }
}
