import XCTest
@testable import LumiTerminal

/// Parser artık YALNIZ byte state machine'dir (Faz 4.8): ham `(code, payload)`
/// üretir. Semantik yorum `OSCSemanticsTests`'te doğrulanır.
final class OSCStreamParserTests: XCTestCase {
    private var parser = OSCStreamParser()

    override func setUp() {
        super.setUp()
        parser = OSCStreamParser()
    }

    private func osc(_ body: String, terminator: String = "\u{07}") -> String {
        "\u{1B}]\(body)\(terminator)"
    }

    // MARK: - Form ve terminatörler

    func testBelTerminatorProducesRawEvent() {
        XCTAssertEqual(
            parser.feed(osc("0;✦ Thinking")),
            [OSCRawEvent(code: 0, payload: "✦ Thinking")]
        )
    }

    func testStTerminatorProducesRawEvent() {
        XCTAssertEqual(
            parser.feed(osc("2;hello", terminator: "\u{1B}\\")),
            [OSCRawEvent(code: 2, payload: "hello")]
        )
    }

    func testSequenceSplitAcrossFeeds() {
        XCTAssertTrue(parser.feed("\u{1B}").isEmpty)
        XCTAssertTrue(parser.feed("]0;he").isEmpty)
        XCTAssertEqual(parser.feed("llo\u{07}").first?.payload, "hello")
    }

    /// Payload'da ";" varsa yalnız İLK ayraçtan bölünür (OSC 8/52 gövdeleri bozulmasın).
    func testPayloadKeepsRemainingSemicolons() {
        XCTAssertEqual(
            parser.feed(osc("52;c;aGVsbG8=")),
            [OSCRawEvent(code: 52, payload: "c;aGVsbG8=")]
        )
    }

    /// Kodu sayıya çözülemeyen gövde sessizce düşer (state machine ground'a döner).
    func testNonNumericCodeIsDropped() {
        XCTAssertTrue(parser.feed(osc("abc;payload")).isEmpty)
        XCTAssertEqual(parser.feed(osc("0;ok")).first?.code, 0)
    }

    /// Ayraçsız gövde: payload boş kalır (OSC 0 "boş title" kararı buna dayanır).
    func testMissingSeparatorYieldsEmptyPayload() {
        XCTAssertEqual(parser.feed(osc("9")), [OSCRawEvent(code: 9, payload: "")])
    }

    // MARK: - Düşürme ve koruma davranışları

    /// Parser artık kod filtrelemez: tanınmayan kodlar semantik katmana ulaşır
    /// (OCP — OSC 7/133 desteği parser'a dokunmadan eklenebilsin).
    func testUnknownCodesReachSemanticLayerAsRawEvents() {
        XCTAssertEqual(parser.feed(osc("7;file:///tmp")).first?.code, 7)
        XCTAssertEqual(parser.feed(osc("8;;http://example.com")).first?.code, 8)
    }

    func testOversizeBufferDiscarded() {
        let big = String(repeating: "a", count: OSCStreamParser.maxBufferLength + 500)
        XCTAssertTrue(parser.feed("\u{1B}]0;" + big + "\u{07}").isEmpty)
        // Parser ground'a döndü; sonraki sequence normal işler
        XCTAssertEqual(parser.feed(osc("0;ok")).first?.payload, "ok")
    }

    func testEscInsideBodyStartsNewSequence() {
        let events = parser.feed("\u{1B}]0;abandoned\u{1B}]2;real\u{07}")
        XCTAssertEqual(events, [OSCRawEvent(code: 2, payload: "real")])
    }

    func testPlainTextAndCSIProduceNothing() {
        XCTAssertTrue(parser.feed("hello \u{1B}[31mworld\u{1B}[0m").isEmpty)
    }

    /// design/01 §6 adım 5: reset yarım sequence'i siler.
    func testResetDropsPartialSequence() {
        XCTAssertTrue(parser.feed("\u{1B}]0;Half").isEmpty)
        parser.reset()
        XCTAssertTrue(parser.feed(" title\u{07}").isEmpty)
    }
}
