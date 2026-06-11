import XCTest
@testable import LumiTerminal

final class UTF8StreamDecoderTests: XCTestCase {
    func testAsciiPassthrough() {
        var decoder = UTF8StreamDecoder()
        XCTAssertEqual(decoder.decode(Data("hello".utf8)), "hello")
    }

    func testSplitIdleMarkAcrossChunks() {
        // ✳ U+2733 = E2 9C B3 — spec/10: bölünmesi OSC parser ve idle tespitini bozar
        var decoder = UTF8StreamDecoder()
        XCTAssertEqual(decoder.decode(Data([0xE2])), "")
        XCTAssertEqual(decoder.decode(Data([0x9C])), "")
        XCTAssertEqual(decoder.decode(Data([0xB3, 0x21])), "\u{2733}!")
    }

    func testSplitFourByteEmoji() {
        var decoder = UTF8StreamDecoder()
        let emoji = Array("🚀".utf8)
        XCTAssertEqual(decoder.decode(Data(emoji[0..<2])), "")
        XCTAssertEqual(decoder.decode(Data(emoji[2...])), "🚀")
    }

    func testMixedTextWithTrailingPartial() {
        var decoder = UTF8StreamDecoder()
        var bytes = Array("abc".utf8)
        bytes += [0xE2, 0x9C]
        XCTAssertEqual(decoder.decode(Data(bytes)), "abc")
        XCTAssertEqual(decoder.decode(Data([0xB3])), "\u{2733}")
    }

    func testInvalidBytesReplacedNotDropped() {
        var decoder = UTF8StreamDecoder()
        let out = decoder.decode(Data([0x80, 0x80, 0x41]))
        XCTAssertTrue(out.hasSuffix("A"))
        XCTAssertTrue(out.contains("\u{FFFD}"))
    }

    func testTwoByteSequenceSplit() {
        var decoder = UTF8StreamDecoder()
        let bytes = Array("ü".utf8) // C3 BC
        XCTAssertEqual(decoder.decode(Data([bytes[0]])), "")
        XCTAssertEqual(decoder.decode(Data([bytes[1]])), "ü")
    }

    func testEmptyData() {
        var decoder = UTF8StreamDecoder()
        XCTAssertEqual(decoder.decode(Data()), "")
    }
}
