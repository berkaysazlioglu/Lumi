import XCTest
@testable import LumiTerminal

final class PTYInputFilterTests: XCTestCase {
    private let filter = PTYInputFilter()

    func testStripsFocusEventsUnconditionally() {
        let input = Data("a\u{1B}[Ib\u{1B}[Oc".utf8)
        XCTAssertEqual(filter.filter(input), Data("abc".utf8))
    }

    func testFocusOnlyChunkBecomesEmpty() {
        XCTAssertEqual(filter.filter(Data("\u{1B}[I".utf8)), Data())
    }

    func testLoneEscapePassesImmediately() {
        // Gerçek ESC tuşu asla bekletilmez (design/01 §4)
        XCTAssertEqual(filter.filter(Data([0x1B])), Data([0x1B]))
    }

    func testArrowKeyPasses() {
        let arrow = Data("\u{1B}[A".utf8)
        XCTAssertEqual(filter.filter(arrow), arrow)
    }

    func testPartialCSIAtChunkEndPasses() {
        let partial = Data([0x1B, 0x5B])
        XCTAssertEqual(filter.filter(partial), partial)
    }

    func testBackspaceBytePasses() {
        // 0x7f (DEL) tuş baytı filtreden aynen geçmeli — backspace regresyon guard'ı
        XCTAssertEqual(filter.filter(Data([0x7F])), Data([0x7F]))
        var suppressing = PTYInputFilter()
        suppressing.suppressResponses = true
        XCTAssertEqual(suppressing.filter(Data([0x7F])), Data([0x7F]))
    }

    func testUTF8TextUntouched() {
        let text = Data("héllo ✳ dünya".utf8)
        XCTAssertEqual(filter.filter(text), text)
    }

    func testCPRPassesWhenSuppressOff() {
        let cpr = Data("\u{1B}[12;40R".utf8)
        XCTAssertEqual(filter.filter(cpr), cpr)
    }

    // MARK: - suppressResponses (defense-in-depth kapısı)

    private var suppressing: PTYInputFilter {
        var f = PTYInputFilter()
        f.suppressResponses = true
        return f
    }

    func testSuppressDropsCPR() {
        XCTAssertEqual(suppressing.filter(Data("a\u{1B}[12;40Rb".utf8)), Data("ab".utf8))
    }

    func testSuppressDropsDAResponse() {
        XCTAssertEqual(suppressing.filter(Data("\u{1B}[?1;2c".utf8)), Data())
    }

    func testSuppressDropsDECRPM() {
        XCTAssertEqual(suppressing.filter(Data("\u{1B}[?2004;1$y".utf8)), Data())
    }

    func testSuppressDropsSGRMouse() {
        XCTAssertEqual(suppressing.filter(Data("\u{1B}[<35;10;20M".utf8)), Data())
        XCTAssertEqual(suppressing.filter(Data("\u{1B}[<35;10;20m".utf8)), Data())
    }

    func testSuppressDropsLegacyMouse() {
        var bytes: [UInt8] = [0x1B, 0x5B, UInt8(ascii: "M")]
        bytes += [32, 33, 34]
        XCTAssertEqual(suppressing.filter(Data(bytes)), Data())
    }

    func testSuppressKeepsOrdinaryCSI() {
        let clear = Data("\u{1B}[2J".utf8)
        XCTAssertEqual(suppressing.filter(clear), clear)
    }

    func testSuppressKeepsPlainY() {
        // '$' intermediate'i olmayan 'y' finali DECRPM değildir
        let notReport = Data("\u{1B}[5y".utf8)
        XCTAssertEqual(suppressing.filter(notReport), notReport)
    }
}
